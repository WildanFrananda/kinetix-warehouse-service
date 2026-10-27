# typed: false

require "rails_helper"

RSpec.describe "how requests this service cannot act on are answered", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-4333-8444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let(:seller) { bearer(access_token(principal_id: principal_id)) }
  let(:relay) { FakeReturnRelay.new }
  let(:order) { FakePackedReport.new }

  before do
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(order)
  end

  describe "a body that is not JSON" do
    it "is a 400, not a 500" do
      patch "/api/v1/merchants/#{merchant.id}",
            params: "{\"cutoff_hour\": ",
            headers: seller.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("INVALID_REQUEST")
    end
  end

  describe "a task that is not the caller's" do
    let(:other_task) { create(:fulfillment_task, merchant: create(:merchant), status: "received") }

    before { create(:fulfillment_task_line, fulfillment_task: other_task, sku: "GAMIS-RED-M") }

    it "is 404 when its status is changed" do
      patch "/api/v1/fulfillment_tasks/#{other_task.id}/status", params: { status: "packing" }, headers: seller

      expect(response).to have_http_status(:not_found)
    end

    it "is 404 when its label is printed" do
      post "/api/v1/fulfillment_tasks/#{other_task.id}/label", headers: seller

      expect(response).to have_http_status(:not_found)
    end

    it "is 404 when it is scanned" do
      post "/api/v1/fulfillment_tasks/#{other_task.id}/verify_scan",
           params: { scanned_code: "GAMIS-RED-M" }, headers: seller

      expect(response).to have_http_status(:not_found)
      expect(other_task.reload.status).to eq("received")
    end
  end

  describe "returned goods whose lines are not a list of objects" do
    before do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)
    end

    def receive_return(lines)
      post "/api/v1/returns/RMA-20261027-0A1B2C3D/received",
           params: { bin_code: "A-01-1", lines: lines }.to_json,
           headers: seller.merge("Content-Type" => "application/json")
    end

    it "refuses a string" do
      receive_return("GAMIS-RED-M")

      expect(response).to have_http_status(:bad_request)
      expect(relay.received).to be_empty
    end

    it "refuses a list of strings" do
      receive_return([ "GAMIS-RED-M" ])

      expect(response).to have_http_status(:bad_request)
      expect(relay.received).to be_empty
    end

    it "refuses a line with no quantity it can count" do
      receive_return([ { sku: "GAMIS-RED-M", quantity: "two" } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(relay.received).to be_empty
    end

    it "refuses a line with no sku" do
      receive_return([ { sku: " ", quantity: 1 } ])

      expect(response).to have_http_status(:unprocessable_content)
      expect(relay.received).to be_empty
    end
  end
end
