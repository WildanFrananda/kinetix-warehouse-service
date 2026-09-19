# typed: strict
# frozen_string_literal: true

require "order/v1/order_services_pb"
require Rails.root.join("lib/kinetix/request_id").to_s
require Rails.root.join("lib/kinetix/service_identity").to_s
require Rails.root.join("lib/kinetix/metrics/grpc_client_recorder").to_s

module Order
  class GrpcClient
    extend T::Sig

    PEER = "order"
    GRPC_METHOD = T.let(
      "/#{::Order::V1::OrderService::Service.service_name}/FulfillmentPacked",
      String
    )

    sig { returns(String) }
    attr_reader :host

    sig { params(host: String).void }
    def initialize(host: ENV.fetch("ORDER_GRPC_HOST"))
      @host = host
    end

    sig do
      params(
        merchant_principal_id: String,
        order_number: String,
        fulfillment_task_id: Integer
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def fulfillment_packed(merchant_principal_id:, order_number:, fulfillment_task_id:)
      stub = ::Order::V1::OrderService::Stub.new(
        @host,
        Kinetix::ServiceIdentity.new.channel_credentials,
        timeout: 5
      )

      req = ::Order::V1::FulfillmentPackedRequest.new(
        merchant_principal_id: merchant_principal_id,
        order_number: order_number,
        fulfillment_task_id: fulfillment_task_id.to_s
      )

      res = Kinetix::Metrics::GrpcClientRecorder.call(peer: PEER, grpc_method: GRPC_METHOD) do
        stub.fulfillment_packed(req, metadata: Kinetix::RequestId.metadata)
      end

      {
        success: res.success,
        already_packed: res.already_packed,
        dispatch_ref: res.dispatch_ref,
        error: res.error&.message
      }
    rescue StandardError => e
      Rails.logger.error("[Order::GrpcClient] FulfillmentPacked failed: #{e.message}")
      { success: false, already_packed: false, dispatch_ref: "", error: e.message }
    end
  end
end
