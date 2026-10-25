# typed: strict

module Fulfillment
  class TaskLookupService < BaseService
    extend T::Sig

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { params(task_repository: FulfillmentTaskRepositoryInterface).void }
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
    )
      super()
      @task_repository = task_repository
    end

    sig { params(merchant_id: Integer, order_number: String).returns(BaseService::Result) }
    def call(merchant_id:, order_number:)
      task = task_repository.find_by_order_number(merchant_id: merchant_id, order_number: order_number)

      success(task ? [ TaskRecordData.of(task) ] : [])
    end
  end
end
