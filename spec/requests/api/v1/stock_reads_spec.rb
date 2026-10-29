# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1 stock reads", type: :request do
  include_context "identity issues tokens"

  let(:staff) { "aaaaaaaa-1111-4222-8333-444444444444" }
  let(:owner) { "bbbbbbbb-1111-4222-8333-444444444444" }
  let(:other_owner) { "cccccccc-1111-4222-8333-444444444444" }
  let(:admin) { bearer(access_token(principal_id: staff, role: "admin")) }

  let!(:shelf_a) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }
  let!(:shelf_b) { WarehouseBin.create!(bin_code: "B-02-3", zone: "B", shelf_level: 3) }
  let!(:empty_shelf) { WarehouseBin.create!(bin_code: "C-01-0", zone: "C", shelf_level: 0) }
  let!(:shirts) do
    BinInventory.create!(
      warehouse_bin: shelf_a, sku: "SHIRT-M", quantity: 10, reserved_quantity: 4, merchant_principal_id: owner
    )
  end
  let!(:caps) do
    BinInventory.create!(
      warehouse_bin: shelf_a, sku: "CAP-1", quantity: 5, reserved_quantity: 0, merchant_principal_id: other_owner
    )
  end
  let!(:sold_out) do
    BinInventory.create!(
      warehouse_bin: shelf_b, sku: "SHIRT-M", quantity: 0, reserved_quantity: 0, merchant_principal_id: owner
    )
  end

  def receipt(bin, sku, quantity, merchant, key)
    StockReceipt.create!(
      warehouse_bin: bin, sku: sku, quantity: quantity, merchant_principal_id: merchant,
      idempotency_key: key, received_by_principal_id: staff, note: "delivery #{key}"
    )
  end

  def adjustment(bin, sku, delta, merchant, key, before:)
    StockAdjustment.create!(
      warehouse_bin: bin, sku: sku, quantity_delta: delta, quantity_before: before, quantity_after: before + delta,
      merchant_principal_id: merchant, idempotency_key: key, reason: "DAMAGE", adjusted_by_principal_id: staff
    )
  end

  describe "who may read the stock" do
    paths = %w[/api/v1/bins /api/v1/bins/stock /api/v1/stock_receipts /api/v1/stock_adjustments]

    paths.each do |path|
      it "refuses #{path} with no token" do
        get path

        expect(response).to have_http_status(:unauthorized)
      end

      it "refuses #{path} to a seller, before reading the query" do
        get path, params: { limit: "0" }, headers: bearer(access_token(principal_id: owner, role: "seller"))

        expect(response).to have_http_status(:forbidden)
      end

      it "refuses #{path} to a customer" do
        get path, headers: bearer(access_token(principal_id: owner, role: "customer"))

        expect(response).to have_http_status(:forbidden)
      end

      it "answers #{path} to an admin" do
        get path, headers: admin

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /api/v1/bins" do
    it "lists every bin by code, with the SKUs it holds and its units" do
      get "/api/v1/bins", headers: admin

      bins = response.parsed_body["bins"]
      expect(bins.map { |bin| bin["bin_code"] }).to eq(%w[A-01-1 B-02-3 C-01-0])
      expect(bins.first).to include(
        "id" => shelf_a.id, "zone" => "A", "shelf_level" => 1,
        "sku_count" => 2, "quantity" => 15, "reserved_quantity" => 4
      )
      expect(bins.second).to include("sku_count" => 0, "quantity" => 0)
      expect(bins.third).to include("sku_count" => 0, "quantity" => 0, "reserved_quantity" => 0)
      expect(response.parsed_body["next_after"]).to be_nil
    end

    it "pages by bin code" do
      get "/api/v1/bins", params: { limit: "2" }, headers: admin

      expect(response.parsed_body["bins"].map { |bin| bin["bin_code"] }).to eq(%w[A-01-1 B-02-3])
      expect(response.parsed_body["next_after"]).to eq("B-02-3")

      get "/api/v1/bins", params: { limit: "2", after: "B-02-3" }, headers: admin

      expect(response.parsed_body["bins"].map { |bin| bin["bin_code"] }).to eq(%w[C-01-0])
      expect(response.parsed_body["next_after"]).to be_nil
    end

    it "says there is no next page when the last page is exactly full" do
      get "/api/v1/bins", params: { limit: "3" }, headers: admin

      expect(response.parsed_body["bins"].length).to eq(3)
      expect(response.parsed_body["next_after"]).to be_nil
    end
  end

  describe "GET /api/v1/bins/stock" do
    it "lists every bin and SKU with what is on hand, reserved and free" do
      get "/api/v1/bins/stock", headers: admin

      rows = response.parsed_body["stock"]
      expect(rows.map { |row| row["id"] }).to eq([ shirts.id, caps.id, sold_out.id ])
      expect(rows.first).to include(
        "bin_code" => "A-01-1", "zone" => "A", "shelf_level" => 1, "sku" => "SHIRT-M",
        "merchant_principal_id" => owner, "quantity" => 10, "reserved_quantity" => 4, "available_quantity" => 6
      )
      expect(response.parsed_body["next_after_id"]).to be_nil
    end

    it "narrows to a SKU, a bin and a merchant, written in any case" do
      get "/api/v1/bins/stock", params: { sku: "SHIRT-M" }, headers: admin
      expect(response.parsed_body["stock"].map { |row| row["id"] }).to eq([ shirts.id, sold_out.id ])

      get "/api/v1/bins/stock", params: { sku: "SHIRT-M", bin_code: "B-02-3" }, headers: admin
      expect(response.parsed_body["stock"].map { |row| row["id"] }).to eq([ sold_out.id ])

      get "/api/v1/bins/stock", params: { merchant_principal_id: other_owner.upcase }, headers: admin
      expect(response.parsed_body["stock"].map { |row| row["id"] }).to eq([ caps.id ])

      get "/api/v1/bins/stock", params: { bin_code: "Z-99" }, headers: admin
      expect(response.parsed_body["stock"]).to eq([])
    end

    it "pages by row id" do
      get "/api/v1/bins/stock", params: { limit: "1" }, headers: admin

      expect(response.parsed_body["next_after_id"]).to eq(shirts.id)

      get "/api/v1/bins/stock", params: { limit: "2", after: shirts.id.to_s }, headers: admin

      expect(response.parsed_body["stock"].map { |row| row["id"] }).to eq([ caps.id, sold_out.id ])
      expect(response.parsed_body["next_after_id"]).to be_nil
    end
  end

  describe "GET /api/v1/stock_receipts" do
    let!(:first) { receipt(shelf_a, "SHIRT-M", 10, owner, "R-1") }
    let!(:second) { receipt(shelf_a, "CAP-1", 5, other_owner, "R-2") }
    let!(:third) { receipt(shelf_b, "SHIRT-M", 3, owner, "R-3") }

    it "lists the receipts newest first, with who booked them" do
      get "/api/v1/stock_receipts", headers: admin

      receipts = response.parsed_body["receipts"]
      expect(receipts.map { |row| row["id"] }).to eq([ third.id, second.id, first.id ])
      expect(receipts.first).to include(
        "bin_code" => "B-02-3", "sku" => "SHIRT-M", "merchant_principal_id" => owner, "quantity" => 3,
        "note" => "delivery R-3", "received_by_principal_id" => staff
      )
      expect(receipts.first["created_at"]).to be_present
      expect(receipts.first).not_to have_key("idempotency_key")
    end

    it "narrows and pages backwards" do
      get "/api/v1/stock_receipts", params: { sku: "SHIRT-M", limit: "1" }, headers: admin

      expect(response.parsed_body["receipts"].map { |row| row["id"] }).to eq([ third.id ])
      expect(response.parsed_body["next_before_id"]).to eq(third.id)

      get "/api/v1/stock_receipts", params: { sku: "SHIRT-M", limit: "1", before: third.id.to_s }, headers: admin

      expect(response.parsed_body["receipts"].map { |row| row["id"] }).to eq([ first.id ])
      expect(response.parsed_body["next_before_id"]).to be_nil
    end
  end

  describe "GET /api/v1/stock_adjustments" do
    let!(:first) { adjustment(shelf_a, "SHIRT-M", -2, owner, "A-1", before: 12) }
    let!(:second) { adjustment(shelf_a, "CAP-1", 1, other_owner, "A-2", before: 4) }

    it "lists the adjustments newest first, with the count before and after" do
      get "/api/v1/stock_adjustments", headers: admin

      adjustments = response.parsed_body["adjustments"]
      expect(adjustments.map { |row| row["id"] }).to eq([ second.id, first.id ])
      expect(adjustments.second).to include(
        "bin_code" => "A-01-1", "sku" => "SHIRT-M", "merchant_principal_id" => owner, "quantity_delta" => -2,
        "quantity_before" => 12, "quantity_after" => 10, "reason" => "DAMAGE", "note" => nil,
        "adjusted_by_principal_id" => staff
      )
    end

    it "narrows to a merchant" do
      get "/api/v1/stock_adjustments", params: { merchant_principal_id: owner }, headers: admin

      expect(response.parsed_body["adjustments"].map { |row| row["id"] }).to eq([ first.id ])
    end
  end

  describe "a query it cannot read" do
    refusals = {
      "a limit of zero" => [ "/api/v1/bins", { limit: "0" }, "INVALID_LIMIT" ],
      "a limit over 100" => [ "/api/v1/bins/stock", { limit: "101" }, "INVALID_LIMIT" ],
      "a limit not in digits" => [ "/api/v1/stock_receipts", { limit: "1e2" }, "INVALID_LIMIT" ],
      "a bin code cursor over 64 characters" => [ "/api/v1/bins", { after: "B" * 65 }, "INVALID_AFTER" ],
      "an empty SKU" => [ "/api/v1/bins/stock", { sku: "" }, "INVALID_SKU" ],
      "a SKU given twice" => [ "/api/v1/bins/stock", { sku: %w[A B] }, "INVALID_SKU" ],
      "a SKU holding a NUL" => [ "/api/v1/stock_receipts", { sku: "A\u0000B" }, "INVALID_SKU" ],
      "a bin code over 64 characters" => [ "/api/v1/stock_adjustments", { bin_code: "B" * 65 }, "INVALID_BIN_CODE" ],
      "a merchant that is no UUID" => [ "/api/v1/bins/stock", { merchant_principal_id: "42" }, "INVALID_MERCHANT_PRINCIPAL_ID" ],
      "a row cursor that is no id" => [ "/api/v1/bins/stock", { after: "12abc" }, "INVALID_AFTER" ],
      "a receipt cursor of zero" => [ "/api/v1/stock_receipts", { before: "0" }, "INVALID_BEFORE" ],
      "an adjustment cursor with a sign" => [ "/api/v1/stock_adjustments", { before: "+5" }, "INVALID_BEFORE" ]
    }

    refusals.each do |name, (path, query, code)|
      it "answers #{name} with 400 #{code}" do
        get path, params: query, headers: admin

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body["error"]).to eq(code)
        expect(response.parsed_body["message"]).to be_present
      end
    end
  end

  it "audits no read: reads are not admin actions" do
    allow(Rails.logger).to receive(:info).and_call_original

    get "/api/v1/bins/stock", headers: admin

    expect(Rails.logger).not_to have_received(:info).with(a_string_starting_with("admin_action"))
  end
end
