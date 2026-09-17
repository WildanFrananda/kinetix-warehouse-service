# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::StockReceipts", type: :request do
  include_context "identity issues tokens"

  let(:principal) { "aaaaaaaa-1111-2222-3333-444444444444" }
  let(:owner) { "bbbbbbbb-1111-2222-3333-444444444444" }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  def post_receipt(headers:, key: "RCV-1", quantity: 5)
    post "/api/v1/stock_receipts",
         params: { bin_code: "A-01-1", sku: "SKU-1", quantity: quantity, idempotency_key: key,
                   merchant_principal_id: owner },
         headers: headers
  end

  describe "who may book goods in" do
    it "refuses a request with no token" do
      post_receipt(headers: {})

      expect(response).to have_http_status(:unauthorized)
      expect(StockReceipt.count).to eq(0)
    end

    it "refuses a customer" do
      token = access_token(principal_id: principal, role: "customer")
      post_receipt(headers: bearer(token))

      expect(response).to have_http_status(:forbidden)
      expect(StockReceipt.count).to eq(0)
    end

    it "refuses a seller" do
      token = access_token(principal_id: principal, role: "seller")
      post_receipt(headers: bearer(token))

      expect(response).to have_http_status(:forbidden)
      expect(StockReceipt.count).to eq(0)
    end

    it "allows an admin" do
      token = access_token(principal_id: principal, role: "admin")
      post_receipt(headers: bearer(token))

      expect(response).to have_http_status(:created)
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(5)
    end
  end

  describe "the write itself" do
    let(:admin) { bearer(access_token(principal_id: principal, role: "admin")) }

    it "books a repeated idempotency key once and says it replayed" do
      post_receipt(headers: admin, key: "SAME", quantity: 5)
      expect(response).to have_http_status(:created)

      post_receipt(headers: admin, key: "SAME", quantity: 5)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["replayed"]).to be(true)

      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(5)
      expect(StockReceipt.count).to eq(1)
    end

    it "requires an idempotency key rather than inventing one" do
      post "/api/v1/stock_receipts",
           params: { bin_code: "A-01-1", sku: "SKU-1", quantity: 5, merchant_principal_id: owner },
           headers: admin

      expect(response).to have_http_status(:bad_request)
      expect(StockReceipt.count).to eq(0)
    end

    it "refuses a bin that does not exist" do
      post "/api/v1/stock_receipts",
           params: { bin_code: "NO-SUCH", sku: "SKU-1", quantity: 5, idempotency_key: "K",
                     merchant_principal_id: owner },
           headers: admin

      expect(response).to have_http_status(:unprocessable_entity)
      expect(WarehouseBin.count).to eq(1)
    end

    it "records the principal that booked it in, taken from the token and not the body" do
      post "/api/v1/stock_receipts",
           params: {
             bin_code: "A-01-1", sku: "SKU-1", quantity: 5, idempotency_key: "K",
             merchant_principal_id: owner,
             received_by_principal_id: "99999999-9999-9999-9999-999999999999"
           },
           headers: admin

      expect(StockReceipt.last.received_by_principal_id).to eq(principal)
    end

    it "records whose goods they are, which is not the person booking them in" do
      post_receipt(headers: admin)

      receipt = StockReceipt.last
      expect(receipt.merchant_principal_id).to eq(owner)
      expect(receipt.received_by_principal_id).to eq(principal)
      expect(BinInventory.find_by(sku: "SKU-1").merchant_principal_id).to eq(owner)
    end

    it "refuses a delivery that does not say whose goods it is" do
      post "/api/v1/stock_receipts",
           params: { bin_code: "A-01-1", sku: "SKU-1", quantity: 5, idempotency_key: "K" },
           headers: admin

      expect(response).to have_http_status(:bad_request)
      expect(StockReceipt.count).to eq(0)
    end
  end
end
