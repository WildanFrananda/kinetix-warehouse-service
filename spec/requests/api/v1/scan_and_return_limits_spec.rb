# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "how long a scanned code and a return's reason may be, and a bin left unnamed", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-3333-4444-999999999999" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, order_number: "ORD-LIMITS-1", status: "received") }
  let(:headers) { bearer(access_token(principal_id: principal_id)).merge("Content-Type" => "application/json") }
  let(:relay) { FakeReturnRelay.new }

  before do
    create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M")
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)
  end

  describe "a scanned code" do
    before do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(FakePackedReport.new)
    end

    def scan(code)
      post "/api/v1/fulfillment_tasks/#{task.id}/verify_scan", params: { scanned_code: code }.to_json, headers: headers
    end

    it "is refused over 128 characters, longer than any SKU, order number or tracking number it could match" do
      scan("S" * 129)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "scanned_code must be at most 128 characters")
      expect(task.reload.status).to eq("received")
    end

    it "is read at 128 characters, where it simply matches nothing" do
      scan("S" * 128)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to start_with("✖ SKU MISMATCH!")
    end
  end

  describe "a return's reason" do
    def open_return(reason)
      post "/api/v1/fulfillment_tasks/#{task.id}/returns", params: { reason: reason }.to_json, headers: headers
    end

    it "is refused over 500 characters, which order would cut, and order is not asked" do
      open_return("r" * 501)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "reason must be at most 500 characters")
      expect(relay.opened).to be_empty
    end

    it "is relayed whole at 500 characters" do
      open_return("r" * 500)

      expect(response).to have_http_status(:created)
      expect(relay.opened.first[:reason]).to eq("r" * 500)
    end

    it "counts a character outside the Basic Multilingual Plane as two, as order counts it" do
      open_return("\u{1F4E6}" * 250)
      expect(response).to have_http_status(:created)

      open_return("\u{1F4E6}" * 251)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "reason must be at most 500 characters")
      expect(relay.opened.length).to eq(1)
    end
  end

  describe "returned goods with no bin named" do
    let(:lines) { [ { sku: "GAMIS-RED-M", quantity: 1 } ] }

    def received(body)
      post "/api/v1/returns/RMA-20261027-0A1B2C3D/received", params: body.to_json, headers: headers
    end

    it "tells order no bin, rather than an empty bin code it made up" do
      received(lines: lines)

      expect(response).to have_http_status(:ok)
      expect(relay.received.first).to include(bin_code: nil)
    end

    it "treats a JSON null bin code as no bin" do
      received(bin_code: nil, lines: lines)

      expect(response).to have_http_status(:ok)
      expect(relay.received.first).to include(bin_code: nil)
    end

    it "refuses a bin code that is only whitespace, and tells order nothing" do
      received(bin_code: "  ", lines: lines)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "bin_code must name the bin the goods went into, or be left out")
      expect(relay.received).to be_empty
    end

    it "is sent to order as an unset field" do
      stub = FakeOrderStub.new
      allow(::Order::V1::OrderService::Stub).to receive(:new).and_return(stub)
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(Order::GrpcClient.new(host: "127.0.0.1:1"))

      received(lines: lines)

      expect(response).to have_http_status(:ok)
      request = stub.requests.last.last
      expect(request.bin_code).to eq("")
      unset = ::Order::V1::ReturnGoodsReceivedRequest.new(request.to_h.except(:bin_code))
      expect(::Order::V1::ReturnGoodsReceivedRequest.encode(request))
        .to eq(::Order::V1::ReturnGoodsReceivedRequest.encode(unset))
    end
  end
end
