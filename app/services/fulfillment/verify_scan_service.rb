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
    end

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { params(task_repository: FulfillmentTaskRepositoryInterface).void }
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    )
      super()
      @task_repository = task_repository
    end

    sig { params(merchant_id: Integer, task_id: Integer, scanned_code: String).returns(BaseService::Result) }
    def call(merchant_id:, task_id:, scanned_code:)
      clean_code = scanned_code.strip
      return failure("Scanned barcode code cannot be blank") if clean_code.blank?

      task = task_repository.find_by_id(merchant_id: merchant_id, id: task_id)
      return failure("Fulfillment task ##{task_id} not found for this merchant") unless task

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
      new_status = task.status == "received" ? "packing" : "packed"
      task_repository.update_status(merchant_id: merchant_id, task_id: task.id, status: new_status)

      matched_sku = matched_line ? T.must(matched_line.sku) : T.must(task.order_number)

      ActionCable.server.broadcast(
        "merchant:fulfillment_tasks:#{merchant_id}",
        {
          event: "fulfillment_task_advanced",
          fulfillment_task_id: task.id,
          order_number: task.order_number,
          status: new_status,
          scanned_sku: matched_sku,
          updated_at: Time.current.iso8601
        }
      )

      success(
        ResultData.new(
          fulfillment_task_id: task.id,
          order_number: T.must(task.order_number),
          matched_sku: matched_sku,
          new_status: new_status,
          message: "✓ MATCHED! #{matched_sku} verified."
        )
      )
    end
  end
end
