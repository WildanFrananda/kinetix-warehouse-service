# typed: strict
# frozen_string_literal: true

module Couriers
  class RequestPickupService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :order_number, String
      const :dispatch_ref, String
      const :driver_principal_id, String
      const :driver_name, String
      const :eta_minutes, Integer
    end

    sig { returns(FleetPulse::GrpcClient) }
    attr_reader :fleet_client

    sig { params(fleet_client: FleetPulse::GrpcClient).void }
    def initialize(fleet_client: T.let(Container[:fleet_pulse_grpc_client], FleetPulse::GrpcClient))
      super()
      @fleet_client = fleet_client
    end

    sig { params(order: Order).returns(BaseService::Result) }
    def call(order:)
      order_number = order.order_number.to_s
      return failure("that order has no order number, so the fleet cannot be told what it is delivering") if order_number.empty?

      destination = order.shipping_address.to_s
      return failure("that order has no shipping address, so there is nowhere to deliver it") if destination.empty?

      owner = order.merchant&.principal_id.to_s
      return failure("that order's merchant has no principal, so the fleet cannot say whose goods these are") if owner.empty?

      result = fleet_client.dispatch_courier(
        order_id: order.id.to_i,
        order_number: order_number,
        pickup_address: pickup_address,
        delivery_address: destination,
        merchant_principal_id: owner
      )

      return failure(result[:error].presence || "the fleet refused the dispatch") unless result[:success]

      driver = result[:driver_principal_id].to_s
      return failure("the fleet reported a dispatch but named no driver principal") if driver.empty?

      success(
        ResultData.new(
          order_number: order_number,
          dispatch_ref: result[:dispatch_ref].to_s,
          driver_principal_id: driver,
          driver_name: result[:driver_name].to_s,
          eta_minutes: result[:eta_minutes].to_i
        )
      )
    end

    private

    sig { returns(String) }
    def pickup_address
      ENV.fetch("WAREHOUSE_PICKUP_ADDRESS")
    end
  end
end
