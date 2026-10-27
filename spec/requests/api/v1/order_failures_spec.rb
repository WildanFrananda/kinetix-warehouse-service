# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "what a client sees when order answers a return with a gRPC error", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"
  include_context "order answers over gRPC"

  let(:principal_id) { "11111111-2222-3333-4444-777777777777" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, order_number: "ORD-RETURN-9") }
  let(:headers) { bearer(access_token(principal_id: principal_id)).merge("Content-Type" => "application/json") }
  let(:orders_words) { "order's own words: row 42 on pgsql-node" }

  def open_return
    post "/api/v1/fulfillment_tasks/#{task.id}/returns", params: { reason: "Wrong size" }.to_json, headers: headers
  end

  def goods_received
    post "/api/v1/returns/#{FakeOrderStub::RETURN_NUMBER}/received",
         params: { bin_code: "A-01-1", lines: [ { sku: "GAMIS-RED-M", quantity: 1 } ] }.to_json,
         headers: headers
  end

  def self.code_name(code)
    GRPC::Core::StatusCodes.constants.find { |name| GRPC::Core::StatusCodes.const_get(name) == code }
  end

  codes = GRPC::Core::StatusCodes
  answers = {
    codes::UNAVAILABLE => [ 503, "ORDER_UNAVAILABLE" ],
    codes::DEADLINE_EXCEEDED => [ 503, "ORDER_TIMEOUT" ],
    codes::RESOURCE_EXHAUSTED => [ 503, "ORDER_UNAVAILABLE" ],
    codes::NOT_FOUND => [ 404, "ORDER_NOT_FOUND" ],
    codes::INVALID_ARGUMENT => [ 422, "ORDER_INVALID_REQUEST" ],
    codes::FAILED_PRECONDITION => [ 409, "ORDER_CONFLICT" ],
    codes::ALREADY_EXISTS => [ 409, "ORDER_CONFLICT" ],
    codes::PERMISSION_DENIED => [ 502, "ORDER_FAILED" ],
    codes::UNAUTHENTICATED => [ 502, "ORDER_FAILED" ],
    codes::INTERNAL => [ 502, "ORDER_FAILED" ],
    codes::UNKNOWN => [ 502, "ORDER_FAILED" ],
    codes::UNIMPLEMENTED => [ 502, "ORDER_FAILED" ],
    codes::CANCELLED => [ 502, "ORDER_FAILED" ],
    codes::ABORTED => [ 502, "ORDER_FAILED" ],
    codes::OUT_OF_RANGE => [ 502, "ORDER_FAILED" ],
    codes::DATA_LOSS => [ 502, "ORDER_FAILED" ]
  }
  messages = {
    "ORDER_UNAVAILABLE" => "order-service could not take this request, so nothing was recorded. Try again shortly.",
    "ORDER_TIMEOUT" => "order-service did not answer in time, so whether it recorded this is not known. Send the " \
                       "same request again to find out: order records a return and its goods once, and answers " \
                       "already_open or already_recorded."
  }

  answers.each do |code, (status, error)|
    describe "order answering #{code_name(code)}" do
      before { order_stub.fail_with(code, orders_words) }

      [ [ "opening a return", :open_return ], [ "reporting returned goods", :goods_received ] ].each do |what, call|
        it "answers #{status} #{error} on #{what}, in warehouse's own words" do
          public_send(call)

          expect(response).to have_http_status(status)
          body = response.parsed_body
          expect(body["error"]).to eq(error)
          expect(body["message"]).to eq(messages.fetch(error)) if messages.key?(error)
          expect(body["message"]).to be_present
          expect(body["traceId"]).to be_present
          expect(response.body).not_to include("order's own words")
          expect(response.body).not_to include("pgsql-node")
          expect(response.headers["Retry-After"]).to eq(status == 503 ? "15" : nil)
        end
      end
    end
  end

  it "covers every status code gRPC defines" do
    defined = GRPC::Core::StatusCodes.constants.map { |name| GRPC::Core::StatusCodes.const_get(name) } - [ codes::OK ]

    expect(answers.keys).to match_array(defined)
  end

  context "when the channel to order cannot be used at all" do
    before { order_stub.raise_error(GRPC::Core::CallError.new("call already invoked")) }

    it "answers 503 ORDER_UNAVAILABLE" do
      open_return

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to eq("ORDER_UNAVAILABLE")
    end
  end

  describe "an answer from order that carries a NUL" do
    it "is refused as order's failure, not passed on as a return number" do
      order_stub.answer(
        :open_return,
        ::Order::V1::OpenReturnResponse.new(success: true, return_number: "RMA-20261027-0A1B\u00002C3D")
      )

      open_return

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to eq("ORDER_FAILED")
      expect(response.body).not_to include("\\u0000")
    end

    it "is refused as order's failure, not passed on as order's reason for a refusal" do
      order_stub.answer(
        :return_goods_received,
        ::Order::V1::ReturnGoodsReceivedResponse.new(
          accepted: false,
          error: ::Common::V1::ErrorDetail.new(error_code: "RETURN_GOODS_REFUSED", message: "no\u0000such return")
        )
      )

      goods_received

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body["error"]).to eq("ORDER_FAILED")
      expect(response.body).not_to include("\\u0000")
    end

    it "leaves a packed parcel packed and says order was not told, rather than showing order's dispatch ref" do
      packing = create(:fulfillment_task, merchant: merchant, order_number: "ORD-PACK-9", status: "packing")
      order_stub.answer(
        :fulfillment_packed,
        ::Order::V1::FulfillmentPackedResponse.new(success: true, dispatch_ref: "DISP-\u00001")
      )

      patch "/api/v1/fulfillment_tasks/#{packing.id}/status", params: { status: "packed" }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(packing.reload.status).to eq("packed")
      expect(response.parsed_body["order_notified"]).to be(false)
      expect(response.parsed_body["dispatch_ref"]).to be_nil
      expect(response.body).not_to include("\\u0000")
    end
  end

  describe "a gRPC error from order when a parcel is packed" do
    it "keeps the task packed and says in fixed words that order was not told" do
      packing = create(:fulfillment_task, merchant: merchant, order_number: "ORD-PACK-8", status: "packing")
      order_stub.fail_with(codes::INVALID_ARGUMENT, orders_words)

      patch "/api/v1/fulfillment_tasks/#{packing.id}/status", params: { status: "packed" }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(packing.reload.status).to eq("packed")
      expect(response.parsed_body["order_notified"]).to be(false)
      expect(response.parsed_body["notify_error"]).to eq(Fulfillment::AdvanceTaskService::ORDER_NOT_TOLD)
    end
  end
end
