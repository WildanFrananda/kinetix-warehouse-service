# typed: false

require "rails_helper"

RSpec.describe "Api::V1::Returns", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-3333-4444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, order_number: "ORD-RETURN-1") }
  let(:valid_headers) { bearer(access_token(principal_id: principal_id)) }

  let(:relay) { FakeReturnRelay.new }

  before do
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)
  end

  describe "POST /api/v1/fulfillment_tasks/:fulfillment_task_id/returns" do
    it "asks order to open the return, and answers with the number order gave" do
      post "/api/v1/fulfillment_tasks/#{task.id}/returns",
           params: { reason: "Wrong size delivered" }, headers: valid_headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["return_number"]).to eq("RMA-20260921-ABCD1234")
      expect(json["fulfillment_task_id"]).to eq(task.id)

      expect(relay.opened).to eq([ {
        merchant_principal_id: principal_id,
        order_number: "ORD-RETURN-1",
        reason: "Wrong size delivered"
      } ])
    end

    it "keeps nothing of its own" do
      post "/api/v1/fulfillment_tasks/#{task.id}/returns",
           params: { reason: "Wrong size delivered" }, headers: valid_headers

      expect(ActiveRecord::Base.connection.table_exists?("returns")).to be false
    end

    it "refuses a return with no stated reason" do
      post "/api/v1/fulfillment_tasks/#{task.id}/returns", params: { reason: "  " }, headers: valid_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(relay.opened).to be_empty
    end

    it "refuses a task that is not this merchant's" do
      other = create(:fulfillment_task, merchant: create(:merchant))

      post "/api/v1/fulfillment_tasks/#{other.id}/returns",
           params: { reason: "Wrong size" }, headers: valid_headers

      expect(response).to have_http_status(:not_found)
      expect(relay.opened).to be_empty
    end

    it "does not report order's refusal as its own decision" do
      relay.refuse_open("that order has no such parcel")

      post "/api/v1/fulfillment_tasks/#{task.id}/returns",
           params: { reason: "Wrong size" }, headers: valid_headers

      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)["error"]).to eq("RETURN_NOT_RECORDED")
    end

    it "answers 200, not 201, when order says that return was already open" do
      relay.already_open!

      post "/api/v1/fulfillment_tasks/#{task.id}/returns",
           params: { reason: "Wrong size" }, headers: valid_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["already_open"]).to be(true)
    end

    context "when order cannot be reached" do
      let(:relay) { Order::GrpcClient.new(host: "127.0.0.1:1") }

      it "answers 503 and does not pass on what the transport said" do
        post "/api/v1/fulfillment_tasks/#{task.id}/returns",
             params: { reason: "Wrong size" }, headers: valid_headers

        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)["error"]).to eq("ORDER_UNAVAILABLE")
        expect(response.body).not_to match(/127\.0\.0\.1|connect|UNAVAILABLE:|14:/)
      end
    end

    it "returns 401 when no token is presented" do
      post "/api/v1/fulfillment_tasks/#{task.id}/returns", params: { reason: "Wrong size delivered" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/returns/:return_number/received" do
    it "reports the physical fact and the bin it went into" do
      post "/api/v1/returns/RMA-20260921-ABCD1234/received",
           params: { bin_code: "A-01-1", lines: [ { sku: "GAMIS-RED-M", quantity: 2 } ] },
           headers: valid_headers

      expect(response).to have_http_status(:ok)

      received = relay.received.first
      expect(received[:return_number]).to eq("RMA-20260921-ABCD1234")
      expect(received[:bin_code]).to eq("A-01-1")
      expect(received[:lines]).to eq([ { sku: "GAMIS-RED-M", quantity: 2 } ])
    end

    context "when order cannot be reached" do
      let(:relay) { Order::GrpcClient.new(host: "127.0.0.1:1") }

      it "answers 503 and does not pass on what the transport said" do
        post "/api/v1/returns/RMA-20260921-ABCD1234/received",
             params: { bin_code: "A-01-1", lines: [ { sku: "GAMIS-RED-M", quantity: 2 } ] },
             headers: valid_headers

        expect(response).to have_http_status(:service_unavailable)
        expect(response.body).not_to match(/127\.0\.0\.1|connect|UNAVAILABLE:|14:/)
      end
    end

    it "refuses to report goods it cannot name" do
      post "/api/v1/returns/RMA-20260921-ABCD1234/received",
           params: { bin_code: "A-01-1" }, headers: valid_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(relay.received).to be_empty
    end

    [ "0x10", "0b11", "1_000", " 3", "3 " ].each do |quantity|
      it "refuses the quantity #{quantity.inspect}, which is not a whole number written in plain digits" do
        post "/api/v1/returns/RMA-20260921-ABCD1234/received",
             params: { bin_code: "A-01-1", lines: [ { sku: "GAMIS-RED-M", quantity: quantity } ] }.to_json,
             headers: valid_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:unprocessable_content)
        expect(relay.received).to be_empty
      end
    end

    context "with a quantity order's contract cannot carry" do
      let(:relay) { Order::GrpcClient.new(host: "127.0.0.1:1") }

      it "refuses it with 422 before building order's request, rather than failing with a 500" do
        lines = [ { sku: "GAMIS-RED-M", quantity: 2_147_483_648 } ]

        post "/api/v1/returns/RMA-20260921-ABCD1234/received",
             params: { bin_code: "A-01-1", lines: lines }.to_json,
             headers: valid_headers.merge("Content-Type" => "application/json")

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it "returns 401 when no token is presented" do
      post "/api/v1/returns/RMA-20260921-ABCD1234/received", params: { bin_code: "A-01-1" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
