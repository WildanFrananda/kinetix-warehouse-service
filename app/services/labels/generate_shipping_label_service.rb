# typed: strict

module Labels
  class GenerateShippingLabelService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :id, Integer
      const :fulfillment_task_id, Integer
      const :awb_number, String
      const :pdf_url, String
      const :reprint_count, Integer
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

    sig do
      params(
        merchant_id: Integer,
        fulfillment_task_id: Integer
      ).returns(BaseService::Result)
    end
    def call(merchant_id:, fulfillment_task_id:)
      task = task_repository.find_by_id(merchant_id: merchant_id, id: fulfillment_task_id)
      return failure("Fulfillment task not found") unless task

      label = task.shipping_label
      if label
        label.increment!(:reprint_count)
      else
        awb = "AWB-#{merchant_id}-#{task.order_number}-#{Time.current.to_i}"
        pdf = "/labels/#{awb}.pdf"
        label = task.create_shipping_label!(
          awb_number: awb,
          pdf_url: pdf,
          reprint_count: 1
        )
      end

      success(
        ResultData.new(
          id: label.id,
          fulfillment_task_id: fulfillment_task_id,
          awb_number: T.must(label.awb_number),
          pdf_url: T.must(label.pdf_url),
          reprint_count: T.must(label.reprint_count)
        )
      )
    end
  end
end
