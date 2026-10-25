# typed: strict

module Fulfillment
  class VerifyScanService < BaseService
    extend T::Sig

    PACKED = "packed"

    class ResultData < T::Struct
      const :fulfillment_task_id, Integer
      const :order_number, String
      const :matched, String
      const :matched_code, String
      const :matched_sku, T.nilable(String)
      const :line_already_scanned, T::Boolean
      const :lines_remaining, Integer
      const :new_status, String
      const :message, String
      const :order_notified, T::Boolean
      const :notify_error, T.nilable(String)
      const :dispatch_ref, T.nilable(String)
    end

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { returns(AdvanceTaskService) }
    attr_reader :advance_task_service

    sig do
      params(
        task_repository: FulfillmentTaskRepositoryInterface,
        advance_task_service: AdvanceTaskService
      ).void
    end
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface),
      advance_task_service: T.let(Container[:advance_task_service], AdvanceTaskService)
    )
      super()
      @task_repository = task_repository
      @advance_task_service = advance_task_service
    end

    sig { params(merchant_id: Integer, task_id: Integer, scanned_code: String).returns(BaseService::Result) }
    def call(merchant_id:, task_id:, scanned_code:)
      clean_code = scanned_code.strip
      return failure("Scanned barcode code cannot be blank") if clean_code.blank?

      task = task_repository.find_by_id(merchant_id: merchant_id, id: task_id)
      return not_found("Fulfillment task ##{task_id} not found for this merchant") unless task

      match = ScanMatch.find(task, clean_code)
      unless match
        expected = task.fulfillment_task_lines.map(&:sku).join(", ")
        return failure("✖ SKU MISMATCH! Scanned '#{clean_code}' does not match expected SKU (#{expected})")
      end

      status = task.status
      unless TaskTransitions.scannable?(status)
        return failure("this task is #{status}; there is nothing left to scan")
      end

      line = match.line
      already = !line.nil? && !task_repository.mark_line_scanned(task_id: task.id, line_id: line.id)
      remaining = task_repository.lines_remaining(task_id: task.id)

      settle(merchant_id: merchant_id, task: task, match: match, already: already, remaining: remaining)
    end

    private

    sig do
      params(
        merchant_id: Integer,
        task: FulfillmentTask,
        match: ScanMatch,
        already: T::Boolean,
        remaining: Integer
      ).returns(BaseService::Result)
    end
    def settle(merchant_id:, task:, match:, already:, remaining:)
      status = task.status
      packed = T.let(nil, T.nilable(AdvanceTaskService::ResultData))

      TaskTransitions.steps_on_scan(from: status, lines_remaining: remaining).each do |step|
        moved = advance_task_service.call(merchant_id: merchant_id, task_id: task.id, new_status: step)
        if moved.success?
          packed = T.cast(moved.data, AdvanceTaskService::ResultData) if step == PACKED
          status = step
          next
        end

        now = task_repository.find_by_id(merchant_id: merchant_id, id: task.id)&.status
        return moved unless now && TaskTransitions.reached?(now, step)

        status = now
      end

      success(
        ResultData.new(
          fulfillment_task_id: task.id,
          order_number: T.must(task.order_number),
          matched: match.kind,
          matched_code: match.code,
          matched_sku: match.line ? match.code : nil,
          line_already_scanned: already,
          lines_remaining: remaining,
          new_status: status,
          message: message(
            match.code,
            already: already,
            remaining: remaining,
            status: status,
            packed: !packed.nil?
          ),
          order_notified: packed ? packed.order_notified : false,
          notify_error: packed&.notify_error,
          dispatch_ref: packed&.dispatch_ref
        )
      )
    end

    sig do
      params(
        code: String,
        already: T::Boolean,
        remaining: Integer,
        status: String,
        packed: T::Boolean
      ).returns(String)
    end
    def message(code, already:, remaining:, status:, packed:)
      head = already ? "#{code} was already scanned." : "✓ MATCHED! #{code} verified."
      return "#{head} Every line is scanned; the parcel is packed." if packed
      return "#{head} The parcel is packed." if status == PACKED

      "#{head} #{remaining} #{remaining == 1 ? 'line' : 'lines'} left to scan."
    end
  end
end
