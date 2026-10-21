# typed: false
# frozen_string_literal: true

require "rails_helper"
require "fulfillment/v1/fulfillment_services_pb"

RSpec.describe "booking stock for a merchant", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:staff) { "aaaaaaaa-1111-4222-8333-444444444444" }
  let(:owner) { "bbbbbbbb-1111-4222-8333-444444444444" }
  let(:admin) { bearer(access_token(principal_id: staff, role: "admin")) }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  def book(key: "RCV-1", sku: "SKU-1", quantity: 5, merchant: owner, bin_code: "A-01-1")
    post "/api/v1/stock_receipts",
         params: {
           bin_code: bin_code,
           sku: sku,
           quantity: quantity,
           idempotency_key: key,
           merchant_principal_id: merchant
         },
         headers: admin
  end

  def adjust(key: "ADJ-1", delta: -1, merchant: owner, bin_code: "A-01-1", reason: "DAMAGE")
    post "/api/v1/stock_adjustments",
         params: {
           bin_code: bin_code,
           sku: "SKU-1",
           quantity_delta: delta,
           reason: reason,
           idempotency_key: key,
           merchant_principal_id: merchant
         },
         headers: admin
  end

  describe "a merchant this service has never seen" do
    it "is projected when its goods are booked, so order can reserve them" do
      expect(Merchant.find_by(principal_id: owner)).to be_nil

      book(quantity: 5)
      expect(response).to have_http_status(:created)

      reply = Rpc::BinStockServiceHandler.new.reserve_stock(
        Fulfillment::V1::ReserveStockRequest.new(
          merchant_principal_id: owner,
          sku: "SKU-1",
          quantity: 2,
          order_number: "ORD-FIRST"
        ),
        nil
      )

      expect(reply.success).to be(true)
      expect(Merchant.find_by(principal_id: owner)).not_to be_nil
    end

    context "when identity knows no merchant with that principal" do
      let(:identity_client) { FakeIdentityClient.new(known: false) }

      it "books nothing" do
        book

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body["error"]).to eq("UNKNOWN_MERCHANT")
        expect(BinInventory.count).to eq(0)
        expect(StockReceipt.count).to eq(0)
      end
    end

    context "when identity cannot be asked" do
      let(:identity_client) { FakeIdentityClient.new(unavailable: true) }

      it "answers 503 and books nothing" do
        book

        expect(response).to have_http_status(:service_unavailable)
        expect(StockReceipt.count).to eq(0)
      end
    end
  end

  describe "the owner's principal" do
    it "refuses one that is not a UUID instead of storing ownerless stock" do
      book(merchant: "not-a-uuid")

      expect(response).to have_http_status(:bad_request)
      expect(BinInventory.count).to eq(0)
    end

    it "treats an upper-case UUID as the same principal" do
      book(key: "RCV-1", quantity: 5)
      book(key: "RCV-2", quantity: 3, merchant: owner.upcase)

      expect(response).to have_http_status(:created)
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(8)

      adjust(merchant: owner.upcase)

      expect(response).to have_http_status(:created)
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(7)
    end

    it "refuses a non-UUID owner on an adjustment" do
      book

      adjust(merchant: "not-a-uuid")

      expect(response).to have_http_status(:bad_request)
      expect(StockAdjustment.count).to eq(0)
    end
  end

  describe "the sku" do
    it "refuses a blank one with a 422, not a 500" do
      book(sku: "   ")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(BinInventory.count).to eq(0)
    end

    it "refuses one longer than a reservation could ever name" do
      book(sku: "S" * (StockOperation::MAX_SKU_LENGTH + 1))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(BinInventory.count).to eq(0)
    end
  end

  describe "an idempotency key used again" do
    it "refuses a different receipt under the same key and books nothing more" do
      book(key: "SAME", quantity: 5)
      book(key: "SAME", quantity: 50)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("IDEMPOTENCY_KEY_CONFLICT")
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(5)
    end

    it "refuses a replay that names another bin instead of reporting that bin as booked" do
      WarehouseBin.create!(bin_code: "B-02-1", zone: "B", shelf_level: 1)
      book(key: "SAME", quantity: 5)

      book(key: "SAME", quantity: 5, bin_code: "B-02-1")

      expect(response).to have_http_status(:conflict)
    end

    it "answers a true replay with the original receipt's bin" do
      book(key: "SAME", quantity: 5)
      book(key: "SAME", quantity: 5)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["bin_code"]).to eq("A-01-1")
      expect(response.parsed_body["replayed"]).to be(true)
    end

    it "is one merchant's, so another merchant's receipt under the same key is booked" do
      other = "cccccccc-1111-4222-8333-444444444444"
      book(key: "SAME", sku: "SKU-1", quantity: 5)

      book(key: "SAME", sku: "SKU-2", quantity: 4, merchant: other)

      expect(response).to have_http_status(:created)
      expect(BinInventory.find_by(sku: "SKU-2").merchant_principal_id).to eq(other)
    end

    it "refuses a different adjustment under the same key" do
      book(quantity: 10)
      adjust(key: "ADJ-SAME", delta: -1)

      adjust(key: "ADJ-SAME", delta: -5)

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("IDEMPOTENCY_KEY_CONFLICT")
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(9)
    end

    it "answers a replayed adjustment with the original's bin" do
      book(quantity: 10)
      adjust(key: "ADJ-SAME", delta: -1)

      adjust(key: "ADJ-SAME", delta: -1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["bin_code"]).to eq("A-01-1")
    end
  end
end
