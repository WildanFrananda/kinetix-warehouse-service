# typed: strict

module Orders
  class UpdateOrderStatusService < BaseService
    extend T::Sig

    PACKED = "packed"

    class ResultData < T::Struct
      const :id, Integer
      const :order_number, String
      const :status, String
      const :updated_at, T.any(Time, ActiveSupport::TimeWithZone)
      const :courier_requested, T::Boolean, default: false
      const :courier_error, T.nilable(String), default: nil
      const :driver_principal_id, T.nilable(String), default: nil
    end

    sig { returns(OrderRepositoryInterface) }
    attr_reader :order_repository

    sig { returns(Couriers::RequestPickupService) }
    attr_reader :request_pickup_service

    sig do
      params(
        order_repository: OrderRepositoryInterface,
        request_pickup_service: Couriers::RequestPickupService
      ).void
    end
    def initialize(
      order_repository: T.let(Container[:order_repository], OrderRepositoryInterface),
      request_pickup_service: T.let(Container[:request_pickup_service], Couriers::RequestPickupService)
    )
      super()
      @order_repository = order_repository
      @request_pickup_service = request_pickup_service
    end

    sig do
      params(
        merchant_id: Integer,
        order_id: Integer,
        new_status: String
      ).returns(BaseService::Result)
    end
    def call(merchant_id:, order_id:, new_status:)
      order = order_repository.find_by_id(merchant_id: merchant_id, id: order_id)
      return failure("Order not found") unless order

      updated_order = order_repository.update_status(merchant_id: merchant_id, order_id: order_id, status: new_status)
      return failure("Failed to update order status") unless updated_order

      updated_at = Time.current
      pickup = new_status == PACKED ? request_pickup(updated_order) : nil

      ActionCable.server.broadcast(
        "merchant:orders:#{merchant_id}",
        {
          order_id: order_id,
          order_number: updated_order.order_number,
          status: new_status,
          updated_at: updated_at.iso8601
        }
      )

      success(
        ResultData.new(
          id: updated_order.id,
          order_number: T.must(updated_order.order_number),
          status: T.must(updated_order.status),
          updated_at: updated_at,
          courier_requested: !pickup.nil? && pickup.success?,
          courier_error: pickup&.success? ? nil : pickup&.error,
          driver_principal_id: dispatched_driver(pickup)
        )
      )
    end

    private

    sig { params(order: Order).returns(BaseService::Result) }
    def request_pickup(order)
      result = request_pickup_service.call(order: order)

      if result.success?
        Rails.logger.info("[Couriers] order #{order.order_number} dispatched: #{T.cast(result.data, Couriers::RequestPickupService::ResultData).dispatch_ref}")
      else
        Rails.logger.error("[Couriers] order #{order.order_number} is packed but no courier was dispatched: #{result.error}")
      end

      result
    rescue StandardError => e
      Rails.logger.error("[Couriers] order #{order.order_number} is packed but the dispatch raised #{e.class}: #{e.message}")
      failure("the fleet could not be reached, so this order is packed but no courier is coming")
    end

    sig { params(pickup: T.nilable(BaseService::Result)).returns(T.nilable(String)) }
    def dispatched_driver(pickup)
      return nil unless pickup&.success?

      T.cast(pickup.data, Couriers::RequestPickupService::ResultData).driver_principal_id
    end
  end
end
