# typed: strict

module Labels
  class GenerateShippingLabelService < BaseService
    extend T::Sig

    CANCELLED = "cancelled"

    class ResultData < T::Struct
      const :id, Integer
      const :fulfillment_task_id, Integer
      const :awb_number, String
      const :print_count, Integer
      const :reprint_count, Integer
    end

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { returns(ShippingLabelRepositoryInterface) }
    attr_reader :label_repository

    sig do
      params(
        task_repository: FulfillmentTaskRepositoryInterface,
        label_repository: ShippingLabelRepositoryInterface
      ).void
    end
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface),
      label_repository: T.let(Container[:shipping_label_repository], ShippingLabelRepositoryInterface)
    )
      super()
      @task_repository = task_repository
      @label_repository = label_repository
    end

    sig do
      params(
        merchant_id: Integer,
        fulfillment_task_id: Integer
      ).returns(BaseService::Result)
    end
    def call(merchant_id:, fulfillment_task_id:)
      task = task_repository.find_by_id(merchant_id: merchant_id, id: fulfillment_task_id)
      return not_found("Fulfillment task not found") unless task
      return failure("This task was cancelled by order; its parcel is not shipped") if task.status == CANCELLED

      label = task.shipping_label
      awb_number = label&.awb_number

      if label.nil? || awb_number.nil?
        return failure(
          "No courier has been assigned to this task yet, so it has no tracking number to print"
        )
      end

      printed = label_repository.record_print(label_id: label.id)

      success(
        ResultData.new(
          id: printed.id,
          fulfillment_task_id: fulfillment_task_id,
          awb_number: awb_number,
          print_count: printed.print_count,
          reprint_count: printed.reprint_count.to_i
        )
      )
    end
  end
end
