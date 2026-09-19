# typed: strict

module Returns
  class InitiateReturnService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :id, Integer
      const :merchant_id, Integer
      const :fulfillment_task_id, Integer
      const :reason, String
      const :status, String
    end

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { returns(ReturnRepositoryInterface) }
    attr_reader :return_repository

    sig do
      params(
        task_repository: FulfillmentTaskRepositoryInterface,
        return_repository: ReturnRepositoryInterface
      ).void
    end
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface),
      return_repository: T.let(Container[:return_repository], ReturnRepositoryInterface)
    )
      super()
      @task_repository = task_repository
      @return_repository = return_repository
    end

    sig do
      params(
        merchant_id: Integer,
        form: InitiateReturnForm
      ).returns(BaseService::Result)
    end
    def call(merchant_id:, form:)
      return failure(form.errors.join(", ")) unless form.valid?

      task = task_repository.find_by_id(merchant_id: merchant_id, id: form.fulfillment_task_id)
      return failure("Fulfillment task not found") unless task

      existing_return = return_repository.find_by_fulfillment_task_id(merchant_id: merchant_id, fulfillment_task_id: form.fulfillment_task_id)
      return failure("Return request already exists for this order") if existing_return

      return_record = return_repository.create(
        merchant_id: merchant_id,
        attributes: {
          fulfillment_task_id: form.fulfillment_task_id,
          reason: form.reason,
          status: "requested"
        }
      )

      success(
        ResultData.new(
          id: return_record.id,
          merchant_id: merchant_id,
          fulfillment_task_id: form.fulfillment_task_id,
          reason: T.must(return_record.reason),
          status: T.must(return_record.status)
        )
      )
    end
  end
end
