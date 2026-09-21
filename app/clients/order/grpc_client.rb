# typed: strict
# frozen_string_literal: true

require "order/v1/order_services_pb"
require Rails.root.join("lib/kinetix/request_id").to_s
require Rails.root.join("lib/kinetix/service_identity").to_s
require Rails.root.join("lib/kinetix/metrics/grpc_client_recorder").to_s

module Order
  class GrpcClient
    extend T::Sig
    include Order::ReturnRelay

    PEER = "order"
    GRPC_METHOD = T.let(
      "/#{::Order::V1::OrderService::Service.service_name}/FulfillmentPacked",
      String
    )
    OPEN_RETURN_METHOD = T.let(
      "/#{::Order::V1::OrderService::Service.service_name}/OpenReturn",
      String
    )
    RETURN_GOODS_METHOD = T.let(
      "/#{::Order::V1::OrderService::Service.service_name}/ReturnGoodsReceived",
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

    sig do
      override.params(
        merchant_principal_id: String,
        order_number: String,
        reason: String
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def open_return(merchant_principal_id:, order_number:, reason:)
      req = ::Order::V1::OpenReturnRequest.new(
        order_number: order_number,
        merchant_principal_id: merchant_principal_id,
        reason: reason
      )

      res = Kinetix::Metrics::GrpcClientRecorder.call(peer: PEER, grpc_method: OPEN_RETURN_METHOD) do
        stub.open_return(req, metadata: Kinetix::RequestId.metadata)
      end

      {
        success: res.success,
        return_number: res.return_number,
        already_open: res.already_open,
        error: res.error&.message
      }
    rescue StandardError => e
      Rails.logger.error("[Order::GrpcClient] OpenReturn failed: #{e.message}")
      { success: false, return_number: "", already_open: false, error: e.message }
    end

    sig do
      override.params(
        merchant_principal_id: String,
        return_number: String,
        lines: T::Array[T::Hash[Symbol, T.untyped]],
        bin_code: String,
        received_at: Time
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def return_goods_received(merchant_principal_id:, return_number:, lines:, bin_code:, received_at:)
      req = ::Order::V1::ReturnGoodsReceivedRequest.new(
        return_number: return_number,
        merchant_principal_id: merchant_principal_id,
        lines: lines.map { |line| ::Order::V1::ReturnedLine.new(sku: line[:sku].to_s, quantity: line[:quantity].to_i) },
        bin_code: bin_code,
        received_at: received_at.utc.iso8601
      )

      res = Kinetix::Metrics::GrpcClientRecorder.call(peer: PEER, grpc_method: RETURN_GOODS_METHOD) do
        stub.return_goods_received(req, metadata: Kinetix::RequestId.metadata)
      end

      {
        accepted: res.accepted,
        already_recorded: res.already_recorded,
        error: res.error&.message
      }
    rescue StandardError => e
      Rails.logger.error("[Order::GrpcClient] ReturnGoodsReceived failed: #{e.message}")
      { accepted: false, already_recorded: false, error: e.message }
    end

    private

    sig { returns(::Order::V1::OrderService::Stub) }
    def stub
      ::Order::V1::OrderService::Stub.new(
        @host,
        Kinetix::ServiceIdentity.new.channel_credentials,
        timeout: 5
      )
    end
  end
end
