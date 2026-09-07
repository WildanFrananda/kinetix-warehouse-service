# typed: strict

require "net/http"
require "json"
require "uri"

module Couriers
  class DispatchFleetPulseService < BaseService
    extend T::Sig

    class ResultData < T::Struct
      const :order_id, Integer
      const :order_number, String
      const :merchant_id, Integer
      const :dispatch_ref, String
      const :status, String
    end

    sig { returns(OrderRepositoryInterface) }
    attr_reader :order_repository

    sig { params(order_repository: OrderRepositoryInterface).void }
    def initialize(
      order_repository: T.let(Container[:order_repository], OrderRepositoryInterface)
    )
      super()
      @order_repository = order_repository
    end

    sig do
      params(
        merchant_id: Integer,
        order_id: Integer,
        fleet_pulse_url: String
      ).returns(BaseService::Result)
    end
    def call(merchant_id:, order_id:, fleet_pulse_url: "http://localhost:4000/api/v1/merchant/orders")
      order = order_repository.find_by_id(merchant_id: merchant_id, id: order_id)
      return failure("Order not found") unless order

      dispatch_ref = "FP-DISPATCH-#{merchant_id}-#{order.id}-#{Time.current.to_i}"

      payload = {
        order_number: order.order_number,
        buyer_name: order.buyer_name,
        buyer_phone: order.buyer_phone,
        shipping_address: order.shipping_address,
        merchant_id: merchant_id,
        dispatch_ref: dispatch_ref
      }

      uri = URI.parse(fleet_pulse_url)
      host = uri.host || "localhost"
      port = uri.port || 4000

      begin
        http = Net::HTTP.new(host, port)
        path = uri.path.to_s.empty? ? "/api/v1/merchant/orders" : uri.path.to_s
        headers = { "Content-Type" => "application/json" }.merge(Kinetix::RequestId.metadata)
        request = Net::HTTP::Post.new(path, headers)
        request.body = payload.to_json
        response = http.request(request)


        if response.is_a?(Net::HTTPSuccess) || response.code.to_i < 400
          success(
            ResultData.new(
              order_id: order_id,
              order_number: T.must(order.order_number),
              merchant_id: merchant_id,
              dispatch_ref: dispatch_ref,
              status: "dispatch_requested"
            )
          )
        else
          failure("FleetPulse API returned status: #{response.code}")
        end
      rescue StandardError => e
        Rails.logger.error(
          "FleetPulse dispatch for order #{order_id} raised #{e.class}: #{e.message} " \
          "(request_id=#{Kinetix::RequestId.current || '-'})"
        )
        failure(
          "FleetPulse could not be reached, so this order was not dispatched and its status is " \
          "unchanged. Try again; the reason is in the log under this request's id."
        )
      end
    end
  end
end
