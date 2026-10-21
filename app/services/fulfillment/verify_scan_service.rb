# typed: strict

module Fulfillment
  class VerifyScanService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :fulfillment_task_id, Integer
      const :order_number, String
      const :matched_sku, String
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

      matched_line = task.fulfillment_task_lines.find { |line| line.sku.to_s.casecmp?(clean_code) }
      awb_match = task.shipping_label&.awb_number&.casecmp?(clean_code)
      order_number_match = task.order_number.to_s.casecmp?(clean_code)

      unless matched_line || awb_match || order_number_match
        expected = task.fulfillment_task_lines.map(&:sku).join(", ")
        return failure("✖ SKU MISMATCH! Scanned '#{clean_code}' does not match expected SKU (#{expected})")
      end

      advance(merchant_id: merchant_id, task: task, matched_line: matched_line)
    end

    private

    sig do
      params(
        merchant_id: Integer,
        task: FulfillmentTask,
        matched_line: T.nilable(FulfillmentTaskLine)
      ).returns(BaseService::Result)
    end
    def advance(merchant_id:, task:, matched_line:)
      current = task.status
      new_status = Fulfillment::TaskTransitions.next_on_scan(current)
      return failure("this task is #{current}; there is nothing left to scan") if new_status.nil?

      moved = advance_task_service.call(merchant_id: merchant_id, task_id: task.id, new_status: new_status)
      return moved if moved.failure?

      advanced = T.cast(moved.data, AdvanceTaskService::ResultData)
      matched_sku = matched_line ? matched_line.sku.to_s : advanced.order_number

      success(
        ResultData.new(
          fulfillment_task_id: advanced.id,
          order_number: advanced.order_number,
          matched_sku: matched_sku,
          new_status: advanced.status,
          message: "✓ MATCHED! #{matched_sku} verified.",
          order_notified: advanced.order_notified,
          notify_error: advanced.notify_error,
          dispatch_ref: advanced.dispatch_ref
        )
      )
    end
  end
end
