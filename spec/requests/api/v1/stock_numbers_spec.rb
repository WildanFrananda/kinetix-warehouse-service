# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "numbers and keys the staff stock routes take", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:staff) { "aaaaaaaa-1111-4222-8333-444444444444" }
  let(:owner) { "bbbbbbbb-1111-4222-8333-444444444444" }
  let(:admin) { bearer(access_token(principal_id: staff, role: "admin")) }
  let(:json_admin) { admin.merge("Content-Type" => "application/json") }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  def receipt(quantity: 5, key: "RCV-1")
    post "/api/v1/stock_receipts",
         params: {
           bin_code: "A-01-1",
           sku: "SKU-1",
           quantity: quantity,
           idempotency_key: key,
           merchant_principal_id: owner
         }.to_json,
         headers: json_admin
  end

  def adjustment(delta: -1, key: "ADJ-1")
    post "/api/v1/stock_adjustments",
         params: {
           bin_code: "A-01-1",
           sku: "SKU-1",
           quantity_delta: delta,
           reason: "MISCOUNT",
           idempotency_key: key,
           merchant_principal_id: owner
         }.to_json,
         headers: json_admin
  end

  def upsert_bin(shelf_level)
    post "/api/v1/bins",
         params: { bin_code: "B-02-1", zone: "B", shelf_level: shelf_level }.to_json,
         headers: json_admin
  end

  def stock(quantity)
    BinInventory.create!(
      warehouse_bin: bin,
      sku: "SKU-1",
      quantity: quantity,
      reserved_quantity: 0,
      merchant_principal_id: owner
    )
  end

  describe "a receipt's quantity" do
    [ true, false, [ 5 ], { "units" => 5 }, 2.9, 5.0, "12abc", "+5", "-5", " 5", "", nil ].each do |quantity|
      it "refuses #{quantity.inspect} with a code and a sentence, and books nothing" do
        receipt(quantity: quantity)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("INVALID_QUANTITY")
        expect(response.parsed_body["message"]).to include("whole number")
        expect(StockReceipt.count).to eq(0)
        expect(BinInventory.count).to eq(0)
      end
    end

    it "refuses one more unit than the column can count, rather than failing with a 500" do
      receipt(quantity: 2_147_483_648)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_QUANTITY")
      expect(StockReceipt.count).to eq(0)
    end

    it "takes the largest count the column holds" do
      receipt(quantity: 2_147_483_647)

      expect(response).to have_http_status(:created)
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(2_147_483_647)
    end

    it "takes a count written as a string of digits, as a form sends it" do
      post "/api/v1/stock_receipts",
           params: {
             bin_code: "A-01-1",
             sku: "SKU-1",
             quantity: "7",
             idempotency_key: "RCV-FORM",
             merchant_principal_id: owner
           },
           headers: admin

      expect(response).to have_http_status(:created)
      expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(7)
    end

    it "refuses a receipt that would take the shelf past what it can count, before writing anything" do
      inventory = stock(2_147_483_000)

      receipt(quantity: 1_000)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("STOCK_LIMIT_EXCEEDED")
      expect(response.parsed_body["message"]).to be_present
      expect(inventory.reload.quantity).to eq(2_147_483_000)
      expect(StockReceipt.count).to eq(0)
    end
  end

  describe "an adjustment's delta" do
    let!(:inventory) { stock(10) }

    [ true, false, [ -1 ], { "units" => -1 }, -2.9, -1.0, "-3abc", "--3", "", nil, 0, "0" ].each do |delta|
      it "refuses #{delta.inspect} with a code and a sentence, and moves nothing" do
        adjustment(delta: delta)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("INVALID_DELTA")
        expect(response.parsed_body["message"]).to include("whole number")
        expect(StockAdjustment.count).to eq(0)
        expect(inventory.reload.quantity).to eq(10)
      end
    end

    it "takes a signed string of digits" do
      adjustment(delta: "-3")

      expect(response).to have_http_status(:created)
      expect(inventory.reload.quantity).to eq(7)
    end

    it "takes an explicit plus sign" do
      adjustment(delta: "+2")

      expect(response).to have_http_status(:created)
      expect(inventory.reload.quantity).to eq(12)
    end

    [ 2_147_483_648, -2_147_483_649 ].each do |delta|
      it "refuses #{delta}, which no integer column holds, rather than failing with a 500" do
        adjustment(delta: delta)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to eq("INVALID_DELTA")
        expect(inventory.reload.quantity).to eq(10)
      end
    end

    it "refuses an increase that would take the shelf past what it can count, before writing anything" do
      adjustment(delta: 2_147_483_647)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("STOCK_LIMIT_EXCEEDED")
      expect(response.parsed_body["message"]).to be_present
      expect(inventory.reload.quantity).to eq(10)
      expect(StockAdjustment.count).to eq(0)
    end
  end

  describe "an idempotency key longer than the ledger stores" do
    it "refuses a receipt's with 422 before writing anything" do
      receipt(key: "K" * 256)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_IDEMPOTENCY_KEY")
      expect(response.parsed_body["message"]).to include("255")
      expect(StockReceipt.count).to eq(0)
      expect(BinInventory.count).to eq(0)
    end

    it "refuses an adjustment's with 422 before writing anything" do
      inventory = stock(10)

      adjustment(key: "K" * 256)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_IDEMPOTENCY_KEY")
      expect(StockAdjustment.count).to eq(0)
      expect(inventory.reload.quantity).to eq(10)
    end

    it "takes a key of exactly 255 characters" do
      receipt(key: "K" * 255)

      expect(response).to have_http_status(:created)
    end
  end

  describe "a bin's shelf level" do
    [ true, false, [ 1 ], { "level" => 1 }, 2.9, 2.0, "3abc", "abc", "-1", -1, 2_147_483_648 ].each do |level|
      it "refuses #{level.inspect} and creates no bin" do
        upsert_bin(level)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("shelf_level")
        expect(WarehouseBin.find_by(bin_code: "B-02-1")).to be_nil
      end
    end

    it "takes a string of digits" do
      upsert_bin("4")

      expect(response).to have_http_status(:created)
      expect(WarehouseBin.find_by(bin_code: "B-02-1").shelf_level).to eq(4)
    end

    it "takes the floor, level 0" do
      upsert_bin(0)

      expect(response).to have_http_status(:created)
      expect(WarehouseBin.find_by(bin_code: "B-02-1").shelf_level).to eq(0)
    end

    it "leaves the level alone when none is sent" do
      upsert_bin(nil)

      expect(response).to have_http_status(:created)
      expect(WarehouseBin.find_by(bin_code: "B-02-1").shelf_level).to eq(1)
    end
  end
end
