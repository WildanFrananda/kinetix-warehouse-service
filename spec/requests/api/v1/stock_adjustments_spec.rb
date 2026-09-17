# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::StockAdjustments", type: :request do
  include_context "identity issues tokens"

  let(:principal) { "aaaaaaaa-1111-2222-3333-444444444444" }
  let(:owner) { "bbbbbbbb-1111-2222-3333-444444444444" }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }
  let!(:inventory) do
    BinInventory.create!(
      warehouse_bin: bin, sku: "SKU-1", quantity: 10, reserved_quantity: 0,
      merchant_principal_id: owner
    )
  end

  def post_adjustment(headers:, key: "ADJ-1", delta: -3, reason: "DAMAGE")
    post "/api/v1/stock_adjustments",
         params: { bin_code: "A-01-1", sku: "SKU-1", quantity_delta: delta, reason: reason,
                   idempotency_key: key, merchant_principal_id: owner },
         headers: headers
  end

  describe "who may adjust stock" do
    it "refuses a request with no token" do
      post_adjustment(headers: {})

      expect(response).to have_http_status(:unauthorized)
      expect(StockAdjustment.count).to eq(0)
      expect(inventory.reload.quantity).to eq(10)
    end

    it "refuses a customer" do
      post_adjustment(headers: bearer(access_token(principal_id: principal, role: "customer")))

      expect(response).to have_http_status(:forbidden)
      expect(inventory.reload.quantity).to eq(10)
    end

    it "refuses a seller" do
      post_adjustment(headers: bearer(access_token(principal_id: principal, role: "seller")))

      expect(response).to have_http_status(:forbidden)
      expect(inventory.reload.quantity).to eq(10)
    end

    it "allows an admin" do
      post_adjustment(headers: bearer(access_token(principal_id: principal, role: "admin")))

      expect(response).to have_http_status(:created)
      expect(inventory.reload.quantity).to eq(7)
    end
  end

  describe "the write itself" do
    let(:admin) { bearer(access_token(principal_id: principal, role: "admin")) }

    it "refuses a write-off that would cut into reserved stock, and says how much is writable" do
      inventory.update!(reserved_quantity: 8)

      post_adjustment(headers: admin, delta: -5)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["max_reduction"]).to eq(2)
      expect(inventory.reload.quantity).to eq(10)
      expect(StockAdjustment.count).to eq(0)
    end

    it "applies a repeated idempotency key once and says it replayed" do
      post_adjustment(headers: admin, key: "SAME", delta: -3)
      expect(response).to have_http_status(:created)

      post_adjustment(headers: admin, key: "SAME", delta: -3)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["replayed"]).to be(true)

      expect(inventory.reload.quantity).to eq(7)
      expect(StockAdjustment.count).to eq(1)
    end

    it "requires an idempotency key rather than inventing one" do
      post "/api/v1/stock_adjustments",
           params: { bin_code: "A-01-1", sku: "SKU-1", quantity_delta: -3, reason: "DAMAGE",
                     merchant_principal_id: owner },
           headers: admin

      expect(response).to have_http_status(:bad_request)
      expect(inventory.reload.quantity).to eq(10)
    end

    it "refuses a reason it does not know rather than storing free text" do
      post_adjustment(headers: admin, reason: "BECAUSE")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(StockAdjustment.count).to eq(0)
    end

    it "refuses an adjustment that does not say whose goods it is" do
      post "/api/v1/stock_adjustments",
           params: { bin_code: "A-01-1", sku: "SKU-1", quantity_delta: -3, reason: "DAMAGE",
                     idempotency_key: "K" },
           headers: admin

      expect(response).to have_http_status(:bad_request)
      expect(StockAdjustment.count).to eq(0)
    end

    it "records the principal that adjusted it, taken from the token and not the body" do
      post "/api/v1/stock_adjustments",
           params: {
             bin_code: "A-01-1", sku: "SKU-1", quantity_delta: -3, reason: "DAMAGE",
             idempotency_key: "K", merchant_principal_id: owner,
             adjusted_by_principal_id: "99999999-9999-9999-9999-999999999999"
           },
           headers: admin

      expect(StockAdjustment.last.adjusted_by_principal_id).to eq(principal)
    end

    it "refuses a sku that is not on that shelf" do
      post "/api/v1/stock_adjustments",
           params: { bin_code: "A-01-1", sku: "SKU-ABSENT", quantity_delta: -1, reason: "DAMAGE",
                     idempotency_key: "K", merchant_principal_id: owner },
           headers: admin

      expect(response).to have_http_status(:unprocessable_entity)
      expect(StockAdjustment.count).to eq(0)
    end
  end
end
