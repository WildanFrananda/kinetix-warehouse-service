# typed: false
# frozen_string_literal: true

require "order/v1/order_services_pb"

class FakeOrderStub < ::Order::V1::OrderService::Stub
  RETURN_NUMBER = "RMA-20261027-0A1B2C3D"

  attr_reader :requests

  def initialize
    @failure = nil
    @answers = {}
    @requests = []
  end

  def fail_with(code, details)
    @failure = GRPC::BadStatus.new_status_exception(code, details)
  end

  def raise_error(error)
    @failure = error
  end

  def answer(rpc, response)
    @answers[rpc] = response
  end

  def open_return(request, metadata: {})
    respond(:open_return, request) do
      ::Order::V1::OpenReturnResponse.new(success: true, return_number: RETURN_NUMBER)
    end
  end

  def return_goods_received(request, metadata: {})
    respond(:return_goods_received, request) { ::Order::V1::ReturnGoodsReceivedResponse.new(accepted: true) }
  end

  def fulfillment_packed(request, metadata: {})
    respond(:fulfillment_packed, request) do
      ::Order::V1::FulfillmentPackedResponse.new(success: true, dispatch_ref: "DISP-1")
    end
  end

  private

  def respond(rpc, request)
    @requests << [ rpc, request ]
    raise @failure if @failure

    @answers.fetch(rpc) { yield }
  end
end

RSpec.shared_context "order answers over gRPC" do
  let(:order_stub) { FakeOrderStub.new }
  let(:order_client) { Order::GrpcClient.new(host: "127.0.0.1:1") }

  before do
    allow(::Order::V1::OrderService::Stub).to receive(:new).and_return(order_stub)
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(order_client)
  end
end
