# typed: strict

module Fulfillment
  class AdvanceTaskService < BaseService
    extend T::Sig

    PACKED = "packed"

    class ResultData < T::Struct
      const :id, Integer
      const :order_number, String
      const :status, String
      const :updated_at, T.any(Time, ActiveSupport::TimeWithZone)
      const :order_notified, T::Boolean, default: false
      const :notify_error, T.nilable(String), default: nil
      const :dispatch_ref, T.nilable(String), default: nil
    end

    sig { returns(FulfillmentTaskRepositoryInterface) }
    attr_reader :task_repository

    sig { returns(::Order::GrpcClient) }
    attr_reader :order_client

    sig do
      params(
        task_repository: FulfillmentTaskRepositoryInterface,
        order_client: ::Order::GrpcClient
      ).void
    end
    def initialize(
      task_repository: T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface),
      order_client: T.let(Container[:order_grpc_client], ::Order::GrpcClient)
    )
      super()
      @task_repository = task_repository
      @order_client = order_client
    end

    sig do
      params(merchant_id: Integer, task_id: Integer, new_status: String).returns(BaseService::Result)
    end
    def call(merchant_id:, task_id:, new_status:)
      unless FulfillmentTask::STATUSES.include?(new_status)
        return failure("#{new_status} is not a state this warehouse can put a task in")
      end

      task = task_repository.find_by_id(merchant_id: merchant_id, id: task_id)
      return failure("Fulfillment task not found") unless task

      updated = task_repository.update_status(merchant_id: merchant_id, task_id: task_id, status: new_status)
      return failure("Failed to update the task") unless updated

      updated_at = Time.current
      notified = new_status == PACKED ? notify_order(updated) : nil

      success(
        ResultData.new(
          id: updated.id,
          order_number: T.must(updated.order_number),
          status: T.must(updated.status),
          updated_at: updated_at,
          order_notified: !notified.nil? && notified[:success],
          notify_error: notified && !notified[:success] ? notified[:error] : nil,
          dispatch_ref: notified && notified[:success] ? notified[:dispatch_ref] : nil
        )
      )
    end

    private

    sig { params(task: FulfillmentTask).returns(T::Hash[Symbol, T.untyped]) }
    def notify_order(task)
      merchant = task.merchant
      principal = merchant&.principal_id

      if principal.blank?
        Rails.logger.error(
          "[Order] task #{task.id} is packed but its merchant has no principal, so order-service " \
          "cannot be told which order this belongs to"
        )
        return { success: false, error: "the merchant has no identity principal", dispatch_ref: "" }
      end

      order_client.fulfillment_packed(
        merchant_principal_id: principal,
        order_number: T.must(task.order_number),
        fulfillment_task_id: task.id
      )
    rescue StandardError => e
      Rails.logger.error("[Order] task #{task.id} is packed but telling order-service raised #{e.class}: #{e.message}")
      { success: false, error: e.message, dispatch_ref: "" }
    end
  end
end
