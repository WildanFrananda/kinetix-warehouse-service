# typed: strict

module Fulfillment
  class AdvanceTaskService < BaseService
    extend T::Sig

    PACKING = "packing"
    PACKED = "packed"
    ORDER_NOT_TOLD = "order-service could not be told this parcel is packed, so no courier has been sent yet. " \
                     "Set the task to packed again to re-send the report."

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
      return failure("status is required: name the state to move the task to") if new_status.strip.empty?

      unless FulfillmentTask::STATUSES.include?(new_status)
        return failure("#{new_status} is not a state this warehouse can put a task in")
      end

      task = task_repository.find_by_id(merchant_id: merchant_id, id: task_id)
      return not_found("Fulfillment task not found") unless task

      current = task.status
      unless Fulfillment::TaskTransitions.merchant_may?(from: current, to: new_status)
        return failure("a #{current} task cannot be moved to #{new_status}")
      end

      if current == PACKING && new_status == PACKED
        remaining = task_repository.lines_remaining(task_id: task.id)
        return failure(unscanned(remaining)) unless remaining.zero?
      end

      updated = task_repository.update_status(
        merchant_id: merchant_id, task_id: task_id, status: new_status, from: current
      )
      return failure("the task changed while this request was being handled; read it again") unless updated

      updated_at = Time.current
      notified = new_status == PACKED ? notify_order(updated) : nil

      success(
        ResultData.new(
          id: updated.id,
          order_number: T.must(updated.order_number),
          status: updated.status,
          updated_at: updated_at,
          order_notified: !notified.nil? && notified[:success],
          notify_error: notified && !notified[:success] ? notified[:error] : nil,
          dispatch_ref: notified && notified[:success] ? notified[:dispatch_ref] : nil
        )
      )
    end

    private

    sig { params(remaining: Integer).returns(String) }
    def unscanned(remaining)
      lines = remaining == 1 ? "1 line of this task has" : "#{remaining} lines of this task have"
      "#{lines} not been scanned; scan every line before the parcel is packed"
    end

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
      Rails.logger.error(
        "[Order] task #{task.id} is packed but telling order-service raised #{e.class}: #{e.message}"
      )
      { success: false, error: ORDER_NOT_TOLD, dispatch_ref: "" }
    end
  end
end
