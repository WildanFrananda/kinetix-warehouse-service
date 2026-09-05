# typed: false

require "rails_helper"

RSpec.describe "Api::V1::Returns", type: :request do
  include_context "identity issues tokens"

  let(:principal_id) { "11111111-2222-3333-4444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let!(:order) { create(:order, merchant: merchant) }
  let(:valid_headers) { bearer(access_token(principal_id: principal_id)) }

  describe "POST /api/v1/orders/:order_id/returns" do
    it "initiates a return request successfully" do
      post "/api/v1/orders/#{order.id}/returns", params: { reason: "Wrong size delivered" }, headers: valid_headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["order_id"]).to eq(order.id)
      expect(json["reason"]).to eq("Wrong size delivered")
      expect(json["status"]).to eq("requested")
    end

    it "returns 401 when no token is presented" do
      post "/api/v1/orders/#{order.id}/returns", params: { reason: "Wrong size delivered" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/returns/:id/status" do
    let!(:return_record) { create(:return, merchant: merchant, order: order) }

    it "updates return status to resolved" do
      patch "/api/v1/returns/#{return_record.id}/status", params: { status: "resolved" }, headers: valid_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["status"]).to eq("resolved")
      expect(json["resolved_at"]).to be_present
    end

    it "returns 401 when no token is presented" do
      patch "/api/v1/returns/#{return_record.id}/status", params: { status: "resolved" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
