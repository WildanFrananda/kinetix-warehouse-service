# typed: strict

module Returns
  class UpdateReturnStatusService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :id, Integer
      const :merchant_id, Integer
      const :fulfillment_task_id, Integer
      const :status, String
      const :resolved_at, T.nilable(T.any(Time, ActiveSupport::TimeWithZone))
    end

    sig { returns(ReturnRepositoryInterface) }
    attr_reader :return_repository

    sig { params(return_repository: ReturnRepositoryInterface).void }
    def initialize(
      return_repository: T.let(Container[:return_repository], ReturnRepositoryInterface)
    )
      super()
      @return_repository = return_repository
    end

    sig do
      params(
        merchant_id: Integer,
        return_id: Integer,
        new_status: String
      ).returns(BaseService::Result)
    end
    def call(merchant_id:, return_id:, new_status:)
      return_record = return_repository.find_by_id(merchant_id: merchant_id, id: return_id)
      return failure("Return request not found") unless return_record

      resolved_at = new_status == "resolved" ? Time.current : nil

      updated_return = return_repository.update_status(
        merchant_id: merchant_id,
        id: return_id,
        status: new_status,
        resolved_at: resolved_at
      )
      return failure("Failed to update return status") unless updated_return

      success(
        ResultData.new(
          id: updated_return.id,
          merchant_id: merchant_id,
          fulfillment_task_id: updated_return.fulfillment_task_id,
          status: T.must(updated_return.status),
          resolved_at: updated_return.resolved_at
        )
      )
    end
  end
end
