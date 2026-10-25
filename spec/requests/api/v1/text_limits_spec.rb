# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "how long a bin code, a zone and a note may be", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:staff) { "aaaaaaaa-1111-4222-8333-777777777777" }
  let(:owner) { "bbbbbbbb-1111-4222-8333-777777777777" }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:admin) { bearer(access_token(principal_id: staff, role: "admin")).merge(json) }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  def upsert_bin(code:, zone: "B")
    post "/api/v1/bins", params: { bin_code: code, zone: zone }.to_json, headers: admin
  end

  def receipt(bin_code: "A-01-1", note: nil)
    post "/api/v1/stock_receipts",
         params: {
           bin_code: bin_code,
           sku: "SKU-1",
           quantity: 5,
           idempotency_key: "RCV-1",
           merchant_principal_id: owner,
           note: note
         }.to_json,
         headers: admin
  end

  def adjustment(bin_code: "A-01-1", note: nil)
    post "/api/v1/stock_adjustments",
         params: {
           bin_code: bin_code,
           sku: "SKU-1",
           quantity_delta: -1,
           reason: "DAMAGE",
           idempotency_key: "ADJ-1",
           merchant_principal_id: owner,
           note: note
         }.to_json,
         headers: admin
  end

  describe "a bin" do
    it "takes a code and a zone of 64 characters" do
      upsert_bin(code: "B" * 64, zone: "Z" * 64)

      expect(response).to have_http_status(:created)
      expect(WarehouseBin.find_by(bin_code: "B" * 64).zone).to eq("Z" * 64)
    end

    it "counts characters, not bytes" do
      upsert_bin(code: "é" * 64, zone: "ü" * 64)

      expect(response).to have_http_status(:created)
    end

    it "refuses a code of 65 characters before writing anything" do
      upsert_bin(code: "B" * 65)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("64")
      expect(WarehouseBin.count).to eq(1)
    end

    it "refuses a zone of 65 characters, for a new bin and for one that exists" do
      upsert_bin(code: "B-02-1", zone: "Z" * 65)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("64")

      upsert_bin(code: "A-01-1", zone: "Z" * 65)

      expect(response).to have_http_status(:unprocessable_content)
      expect(WarehouseBin.count).to eq(1)
      expect(bin.reload.zone).to eq("A")
    end
  end

  describe "a receipt" do
    it "takes a note of 1000 characters" do
      receipt(note: "n" * 1000)

      expect(response).to have_http_status(:created)
      expect(StockReceipt.last.note).to eq("n" * 1000)
    end

    it "refuses a note of 1001 characters with INVALID_NOTE, before writing anything" do
      receipt(note: "n" * 1001)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_NOTE")
      expect(response.parsed_body["message"]).to include("1000")
      expect(StockReceipt.count).to eq(0)
      expect(BinInventory.count).to eq(0)
    end

    it "refuses a bin code no bin can have with INVALID_BIN_CODE" do
      receipt(bin_code: "B" * 65)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_BIN_CODE")
      expect(response.parsed_body["message"]).to include("64")
    end
  end

  describe "an adjustment" do
    let!(:inventory) do
      BinInventory.create!(
        warehouse_bin: bin,
        sku: "SKU-1",
        quantity: 10,
        reserved_quantity: 0,
        merchant_principal_id: owner
      )
    end

    it "takes a note of 1000 characters" do
      adjustment(note: "n" * 1000)

      expect(response).to have_http_status(:created)
      expect(StockAdjustment.last.note).to eq("n" * 1000)
    end

    it "refuses a note of 1001 characters with INVALID_NOTE, before moving anything" do
      adjustment(note: "n" * 1001)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_NOTE")
      expect(StockAdjustment.count).to eq(0)
      expect(inventory.reload.quantity).to eq(10)
    end

    it "refuses a bin code no bin can have with INVALID_BIN_CODE" do
      adjustment(bin_code: "B" * 65)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_BIN_CODE")
      expect(inventory.reload.quantity).to eq(10)
    end
  end

  describe "returned goods" do
    let(:relay) { FakeReturnRelay.new }

    before do
      create(:merchant, principal_id: owner)
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)
    end

    it "refuses a bin code no bin can have, and tells order nothing" do
      post "/api/v1/returns/RMA-1/received",
           params: { bin_code: "B" * 65, lines: [ { sku: "SKU-1", quantity: 1 } ] }.to_json,
           headers: bearer(access_token(principal_id: owner)).merge(json)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("bin_code must be at most 64 characters")
      expect(relay.received).to be_empty
    end
  end

  describe "the database" do
    def insert(model, row)
      ActiveRecord::Base.transaction(requires_new: true) do
        model.insert_all([ row.merge(created_at: Time.current, updated_at: Time.current) ])
      end
    end

    it "refuses a bin code or a zone longer than 64 characters from any path" do
      expect { insert(WarehouseBin, bin_code: "B" * 65, zone: "B", shelf_level: 1) }
        .to raise_error(ActiveRecord::ValueTooLong)
      expect { insert(WarehouseBin, bin_code: "B-02-1", zone: "Z" * 65, shelf_level: 1) }
        .to raise_error(ActiveRecord::ValueTooLong)
    end

    it "refuses a note longer than 1000 characters from any path" do
      note = "n" * 1001
      receipt_row = {
        warehouse_bin_id: bin.id,
        sku: "SKU-1",
        quantity: 1,
        idempotency_key: "RCV-DB",
        received_by_principal_id: staff,
        merchant_principal_id: owner,
        note: note
      }
      adjustment_row = {
        warehouse_bin_id: bin.id,
        sku: "SKU-1",
        merchant_principal_id: owner,
        quantity_delta: -1,
        reason: "DAMAGE",
        idempotency_key: "ADJ-DB",
        adjusted_by_principal_id: staff,
        quantity_before: 2,
        quantity_after: 1,
        note: note
      }

      expect { insert(StockReceipt, receipt_row) }.to raise_error(ActiveRecord::ValueTooLong)
      expect { insert(StockAdjustment, adjustment_row) }.to raise_error(ActiveRecord::ValueTooLong)
    end
  end
end
