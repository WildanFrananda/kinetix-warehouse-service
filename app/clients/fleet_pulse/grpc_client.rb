# typed: strict
# frozen_string_literal: true

require_relative "../../../lib/generated/fleet/v1/courier_telemetry_services_pb"

module FleetPulse
  class GrpcClient
    extend T::Sig

    sig { returns(String) }
    attr_reader :host

    sig { params(host: String).void }
    def initialize(host: ENV.fetch("MATCHING_GRPC_HOST", "localhost:50053"))
      @host = host
    end

    sig do
      params(
        order_id: Integer,
        order_number: String,
        pickup_address: String,
        delivery_address: String
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def dispatch_courier(order_id:, order_number:, pickup_address:, delivery_address:)
      stub = Fleet::V1::CourierTelemetryService::Stub.new(
        @host,
        :this_channel_is_insecure,
        timeout: 5
      )

      req = Fleet::V1::DispatchCourierRequest.new(
        merchant_api_key: "INTERNAL_OMS_KEY",
        order_id: order_id,
        order_number: order_number,
        pickup_address: Common::V1::Address.new(street_address: pickup_address),
        delivery_address: Common::V1::Address.new(street_address: delivery_address)
      )

      res = stub.dispatch_courier(req)

      {
        success: res.success,
        dispatch_ref: res.dispatch_ref,
        driver_name: res.assigned_driver_name,
        driver_phone: res.assigned_driver_phone,
        vehicle: res.vehicle,
        eta_minutes: res.eta_minutes
      }
    rescue StandardError => e
      Rails.logger.error("[FleetPulse::GrpcClient] Dispatch failed: #{e.message}")
      {
        success: false,
        dispatch_ref: "",
        driver_name: "",
        driver_phone: "",
        vehicle: "",
        eta_minutes: 0,
        error: e.message
      }
    end
  end
end
