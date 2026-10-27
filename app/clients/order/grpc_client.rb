# typed: strict
# frozen_string_literal: true

require "order/v1/order_services_pb"
require Rails.root.join("lib/kinetix/request_id").to_s
require Rails.root.join("lib/kinetix/service_identity").to_s
require Rails.root.join("lib/kinetix/proto_nul").to_s
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
    UNAVAILABLE_CODES = T.let(
      [ GRPC::Core::StatusCodes::UNAVAILABLE, GRPC::Core::StatusCodes::RESOURCE_EXHAUSTED ].freeze,
      T::Array[Integer]
    )
    UNREACHABLE = T.let(
      [ GRPC::Core::CallError, SocketError, IOError ].freeze,
      T::Array[T.class_of(Exception)]
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

      res = ask("FulfillmentPacked", GRPC_METHOD) do
        stub.fulfillment_packed(req, metadata: Kinetix::RequestId.metadata)
      end

      {
        success: res.success,
        already_packed: res.already_packed,
        dispatch_ref: res.dispatch_ref,
        error: res.error&.message
      }
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

      res = ask("OpenReturn", OPEN_RETURN_METHOD) do
        stub.open_return(req, metadata: Kinetix::RequestId.metadata)
      end

      {
        success: res.success,
        return_number: res.return_number,
        already_open: res.already_open,
        error: res.error&.message
      }
    end

    sig do
      override.params(
        merchant_principal_id: String,
        return_number: String,
        lines: T::Array[T::Hash[Symbol, T.untyped]],
        bin_code: T.nilable(String),
        received_at: Time
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def return_goods_received(merchant_principal_id:, return_number:, lines:, bin_code:, received_at:)
      returned = lines.map do |line|
        ::Order::V1::ReturnedLine.new(sku: line[:sku].to_s, quantity: line[:quantity].to_i)
      end
      req = ::Order::V1::ReturnGoodsReceivedRequest.new(
        return_number: return_number,
        merchant_principal_id: merchant_principal_id,
        lines: returned,
        bin_code: bin_code,
        received_at: received_at.utc.iso8601
      )

      res = ask("ReturnGoodsReceived", RETURN_GOODS_METHOD) do
        stub.return_goods_received(req, metadata: Kinetix::RequestId.metadata)
      end

      {
        accepted: res.accepted,
        already_recorded: res.already_recorded,
        error: res.error&.message
      }
    end

    private

    sig do
      type_parameters(:Response)
        .params(
          rpc: String,
          grpc_method: String,
          blk: T.proc.returns(T.type_parameter(:Response))
        )
        .returns(T.type_parameter(:Response))
    end
    def ask(rpc, grpc_method, &blk)
      response = Kinetix::Metrics::GrpcClientRecorder.call(peer: PEER, grpc_method: grpc_method, &blk)

      field = Kinetix::ProtoNul.field(response)
      raise Order::CallFailed.new(rpc, Order::Failure::Failed, "its answer carries a NUL in #{field}") if field

      response
    rescue GRPC::BadStatus => e
      raise Order::TimedOut.new(rpc, e.message) if e.code == GRPC::Core::StatusCodes::DEADLINE_EXCEEDED
      raise Order::Unavailable.new(rpc, e.message) if UNAVAILABLE_CODES.include?(e.code)

      raise Order::CallFailed.new(rpc, Order::Failure.of(e.code), e.message)
    rescue *UNREACHABLE => e
      raise Order::Unavailable.new(rpc, e.message)
    end

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
