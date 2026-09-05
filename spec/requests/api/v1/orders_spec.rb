# typed: false

require "rails_helper"

RSpec.describe "Api::V1::Orders", type: :request do
  include_context "identity issues tokens"

  let(:principal_id) { "11111111-2222-3333-4444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let(:valid_headers) { bearer(access_token(principal_id: principal_id)) }

  describe "POST /api/v1/orders" do
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

    it "attributes the order to the merchant the token's principal names" do
      post "/api/v1/orders", params: valid_payload, headers: valid_headers

      expect(Order.find(JSON.parse(response.body)["id"]).merchant_id).to eq(merchant.id)
    end

    it "returns 401 when no token is presented" do
      post "/api/v1/orders", params: valid_payload

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a token signed by a key identity did not publish" do
      forged = JWT.encode(
        {
          sub: principal_id, uid: 1, email: "seller@kinetix.test", role: "seller",
          token_use: "access", iss: ENV.fetch("JWT_ISSUER"), aud: ENV.fetch("JWT_AUDIENCE"),
          exp: Time.now.to_i + 900
        },
        OpenSSL::PKey::RSA.generate(2048), "RS256", kid: IdentityTokens::JWK.kid
      )

      post "/api/v1/orders", params: valid_payload, headers: bearer(forged)

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for a refresh token, which is long-lived by design" do
      post "/api/v1/orders", params: valid_payload,
                             headers: bearer(access_token(principal_id: principal_id, token_use: "refresh"))

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 for an expired token" do
      post "/api/v1/orders", params: valid_payload,
                             headers: bearer(access_token(principal_id: principal_id, exp: Time.now.to_i - 1))

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 for a valid token whose principal is linked to no merchant here" do
      post "/api/v1/orders", params: valid_payload,
                             headers: bearer(access_token(principal_id: "99999999-9999-9999-9999-999999999999"))

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for a customer, whose token is valid but carries no merchant authority" do
      post "/api/v1/orders", params: valid_payload,
                             headers: bearer(access_token(principal_id: principal_id, role: "customer"))

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/orders/queue" do
    let!(:order) { create(:order, merchant: merchant) }

    it "returns list of orders in queue" do
      get "/api/v1/orders/queue", headers: valid_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json).to be_an(Array)
      expect(json.first["order_number"]).to eq(order.order_number)
    end

    it "does not return another merchant's orders" do
      other = create(:merchant, principal_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
      create(:order, merchant: other, order_number: "ORD-OTHER-1")

      get "/api/v1/orders/queue", headers: valid_headers

      numbers = JSON.parse(response.body).map { |o| o["order_number"] }
      expect(numbers).to include(order.order_number)
      expect(numbers).not_to include("ORD-OTHER-1")
    end
  end
end
