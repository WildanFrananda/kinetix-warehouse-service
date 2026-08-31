# typed: false

require "rails_helper"

RSpec.describe "Api::V1::Orders", type: :request do
  let!(:merchant) { create(:merchant, api_key: "valid_api_key_123") }

  describe "POST /api/v1/orders" do
    let(:valid_headers) { { "X-Merchant-Api-Key" => "valid_api_key_123" } }
    let(:valid_payload) do
      {
        order_number: "ORD-9999",
        buyer_name: "Siti Rahma",
        buyer_phone: "081987654321",
        shipping_address: "Jl. Mawar No. 10, Bandung",
        total_amount: "250000.0",
        items: [
          {
            sku: "HIJAB-BLK-1",
            product_name: "Hijab Silk Black",
            quantity: 2,
            price: "125000.0"
          }
        ]
      }
    end

    it "creates a new order successfully" do
      post "/api/v1/orders", params: valid_payload, headers: valid_headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["order_number"]).to eq("ORD-9999")
      expect(json["status"]).to be_present
    end

    it "returns 401 unauthorized when API key is missing" do
      post "/api/v1/orders", params: valid_payload

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/orders/queue" do
    let(:valid_headers) { { "X-Merchant-Api-Key" => "valid_api_key_123" } }
    let!(:order) { create(:order, merchant: merchant) }

    it "returns list of orders in queue" do
      get "/api/v1/orders/queue", headers: valid_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first["order_number"]).to eq(order.order_number)
    end
  end
end
