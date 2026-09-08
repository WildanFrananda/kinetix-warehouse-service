# typed: false
# frozen_string_literal: true

require "rails_helper"
require "fulfillment/v1/fulfillment_services_pb"
require_relative "../../app/rpc/bin_stock_service_handler"

RSpec.describe Rpc::BinStockServiceHandler do
  let(:handler) { described_class.new }
  let(:principal) { "aaaaaaaa-1111-2222-3333-444444444444" }

  let!(:merchant) do
    Merchant.create!(name: "Bin Merchant", code: "BIN-1", cutoff_hour: 14, principal_id: principal)
  end

  let!(:bin) { WarehouseBin.create!(bin_code: "A-01", zone: "A", shelf_level: 1) }
  let!(:inventory) do
    BinInventory.create!(warehouse_bin: bin, sku: "SKU-1", quantity: 10, reserved_quantity: 0)
  end

  def reserve(quantity: 2, order_number: "ORD-1", sku: "SKU-1", key: nil, principal_id: principal)
    handler.reserve_stock(
      Fulfillment::V1::ReserveStockRequest.new(
        merchant_principal_id: principal_id,
        sku: sku,
        quantity: quantity,
        order_number: order_number,
        idempotency_key: key ? Common::V1::IdempotencyKey.new(key: key) : nil
      ), nil
    )
  end

  def release(quantity: 2, order_number: "ORD-1", sku: "SKU-1", key: nil, principal_id: principal)
    handler.release_stock(
      Fulfillment::V1::ReleaseStockRequest.new(
        merchant_principal_id: principal_id,
        sku: sku,
        quantity: quantity,
        order_number: order_number,
        idempotency_key: key ? Common::V1::IdempotencyKey.new(key: key) : nil
      ), nil
    )
  end

  describe "#reserve_stock" do
    it "reserves against the bin that holds the sku and records which bin it took from" do
      res = reserve(quantity: 3)

      expect(res.success).to be(true)
      expect(res.bin_location).to eq("A-01")
      expect(res.remaining_available).to eq(7)
      expect(inventory.reload.reserved_quantity).to eq(3)
      expect(StockReservation.last.bin_inventory_id).to eq(inventory.id)
    end

    it "never attaches an ErrorDetail to a successful reply" do
      expect(reserve.has_error?).to be(false)
    end

    it "moves the counter once when the same key arrives twice, and replays the exact bytes" do
      first = reserve(quantity: 3, key: "K-1")
      second = reserve(quantity: 3, key: "K-1")

      expect(second.to_proto).to eq(first.to_proto)
      expect(inventory.reload.reserved_quantity).to eq(3)
      expect(StockReservation.count).to eq(1)
      expect(StockOperation.count).to eq(1)
      expect(StockOperation.first.replay_count).to eq(1)
    end

    it "deduplicates a key-less caller on the derived key, so nothing has to change upstream" do
      first = reserve(quantity: 3)
      second = reserve(quantity: 3)

      expect(second.to_proto).to eq(first.to_proto)
      expect(inventory.reload.reserved_quantity).to eq(3)
      expect(StockOperation.pluck(:idempotency_key)).to eq([ "reserve:ORD-1:SKU-1" ])
    end

    it "refuses a key reused for a different quantity and changes nothing" do
      reserve(quantity: 3, key: "K-1")
      res = reserve(quantity: 8, key: "K-1")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("IDEMPOTENCY_KEY_CONFLICT")
      expect(inventory.reload.reserved_quantity).to eq(3)
      expect(StockReservation.count).to eq(1)
      expect(StockOperation.first.conflict_count).to eq(1)
    end

    it "refuses a second reserve of a different quantity under the same order and sku" do
      reserve(quantity: 3, key: "K-1")
      res = reserve(quantity: 8, key: "K-2")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("RESERVATION_QUANTITY_MISMATCH")
      expect(inventory.reload.reserved_quantity).to eq(3)
    end

    it "does not re-hold stock for an order that was already released" do
      reserve(quantity: 3, key: "K-1")
      release(key: "R-1")

      res = reserve(quantity: 3, key: "K-2")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("STOCK_RESERVATION_RELEASED")
      expect(inventory.reload.reserved_quantity).to eq(0)
      expect(StockReservation.first.released_at).to be_present
    end

    it "does not replay a stored success once the ledger has let the stock go" do
      reserve(quantity: 3, key: "K-1")
      release(key: "R-1")

      res = reserve(quantity: 3, key: "K-1")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("STOCK_RESERVATION_RELEASED")
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "refuses a request with no order number and holds nothing" do
      res = reserve(order_number: "")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
      expect(inventory.reload.reserved_quantity).to eq(0)
      expect(StockReservation.count).to eq(0)
      expect(StockOperation.count).to eq(0)
    end

    it "refuses a key longer than the column can hold, and says so about the key" do
      res = reserve(key: "x" * (StockOperation::MAX_KEY_LENGTH + 1))

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
      expect(res.error.message).to include("idempotency_key")
      expect(StockOperation.count).to eq(0)
    end

    it "names order_number, not idempotency_key, when the order number is too long" do
      res = reserve(order_number: "O" * (StockOperation::MAX_ORDER_NUMBER_LENGTH + 1))

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
      expect(res.error.message).to include("order_number")
      expect(res.error.message).not_to include("idempotency_key")
      expect(StockOperation.count).to eq(0)
      expect(StockReservation.count).to eq(0)
    end

    it "refuses an over-long sku by name instead of dying inside the INSERT" do
      res = reserve(sku: "S" * 3_000, key: "k1")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
      expect(res.error.message).to include("sku")
      expect(StockOperation.count).to eq(0)
      expect(StockReservation.count).to eq(0)
    end

    it "refuses an over-long sku on release too, before any tombstone is written" do
      res = release(sku: "S" * 3_000, key: "k1")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
      expect(res.error.message).to include("sku")
      expect(StockReservation.count).to eq(0)
    end

    it "accepts identifiers exactly at the limit" do
      order_number = "O" * StockOperation::MAX_ORDER_NUMBER_LENGTH
      sku = "S" * StockOperation::MAX_SKU_LENGTH
      BinInventory.create!(warehouse_bin: bin, sku: sku, quantity: 5, reserved_quantity: 0)

      res = reserve(quantity: 1, order_number: order_number, sku: sku)

      expect(res.success).to be(true)
      expect(StockOperation.first.idempotency_key.length)
        .to be <= StockOperation::MAX_KEY_LENGTH
    end

    it "counts a refused replay separately from a served one" do
      reserve(quantity: 3, key: "K-1")
      release(key: "R-1")

      res = reserve(quantity: 3, key: "K-1")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("STOCK_RESERVATION_RELEASED")

      record = StockOperation.find_by(operation: StockOperation::RESERVE, idempotency_key: "K-1")
      expect(record.replay_refused_count).to eq(1)
      expect(record.replay_count).to eq(0)
      expect(record.last_replay_request_id).not_to be_nil
    end

    it "logs a refused replay under its own anchor rather than as a plain replay" do
      reserve(quantity: 3, key: "K-1")
      release(key: "R-1")

      allow(Rails.logger).to receive(:error)
      allow(Rails.logger).to receive(:warn)

      reserve(quantity: 3, key: "K-1")

      expect(Rails.logger).to have_received(:error)
        .with(/stock\.idem replay_refused error_code=STOCK_RESERVATION_RELEASED/)
      expect(Rails.logger).not_to have_received(:warn).with(/stock\.idem replay /)
    end

    it "refuses a non-positive quantity" do
      res = reserve(quantity: 0)

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
    end

    it "refuses a principal no merchant here is linked to" do
      res = reserve(principal_id: "bbbbbbbb-0000-0000-0000-000000000000")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("UNKNOWN_MERCHANT")
    end

    it "refuses a sku no bin carries" do
      res = reserve(sku: "SKU-ABSENT")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("SKU_NOT_STOCKED")
    end

    it "does not memoise a refusal, so a restock lets the same key through" do
      res = reserve(quantity: 40, key: "K-1")
      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INSUFFICIENT_STOCK")
      expect(StockOperation.count).to eq(0)
      expect(StockReservation.count).to eq(0)

      inventory.update!(quantity: 100)
      expect(reserve(quantity: 40, key: "K-1").success).to be(true)
    end

    it "refuses with the largest single bin, not the sku total the caller cannot order" do
      second = WarehouseBin.create!(bin_code: "A-02", zone: "A", shelf_level: 1)
      BinInventory.create!(warehouse_bin: second, sku: "SKU-SPLIT", quantity: 4, reserved_quantity: 0)
      third = WarehouseBin.create!(bin_code: "A-03", zone: "A", shelf_level: 1)
      BinInventory.create!(warehouse_bin: third, sku: "SKU-SPLIT", quantity: 4, reserved_quantity: 0)

      res = reserve(quantity: 5, sku: "SKU-SPLIT")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INSUFFICIENT_STOCK")
      expect(res.remaining_available).to eq(4)
      expect(res.error.message).to include("the largest single bin holds 4")

      expect(reserve(quantity: 4, sku: "SKU-SPLIT", order_number: "ORD-SPLIT").success).to be(true)
    end

    it "fills from a bin that can cover the order rather than the first one it finds" do
      empty = WarehouseBin.create!(bin_code: "A-00", zone: "A", shelf_level: 1)
      BinInventory.create!(warehouse_bin: empty, sku: "SKU-2", quantity: 0, reserved_quantity: 0)
      stocked = WarehouseBin.create!(bin_code: "Z-99", zone: "Z", shelf_level: 1)
      full = BinInventory.create!(
        warehouse_bin: stocked, sku: "SKU-2", quantity: 50, reserved_quantity: 0
      )

      res = reserve(quantity: 5, sku: "SKU-2")

      expect(res.success).to be(true)
      expect(res.bin_location).to eq("Z-99")
      expect(full.reload.reserved_quantity).to eq(5)
    end

    it "gives each merchant its own row for the same order number, and never shares a hold" do
      other = Merchant.create!(
        name: "Other", code: "BIN-2", cutoff_hour: 14,
        principal_id: "cccccccc-0000-0000-0000-000000000000"
      )
      reserve(quantity: 3, key: "K-A")

      res = reserve(quantity: 3, key: "K-B", principal_id: other.principal_id)

      expect(res.success).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(6)
      expect(StockReservation.where(order_number: "ORD-1", sku: "SKU-1").count).to eq(2)
      expect(StockReservation.where(merchant_id: merchant.id).pluck(:quantity)).to eq([ 3 ])
      expect(StockReservation.where(merchant_id: other.id).pluck(:quantity)).to eq([ 3 ])
    end

    it "records only the attempt that moved the counter as applied" do
      first = reserve(quantity: 3, key: "K-1")
      second = reserve(quantity: 3, key: "K-2")

      expect(first.success).to be(true)
      expect(second.success).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(3)

      reserves = StockOperation.where(operation: StockOperation::RESERVE)
      expect(reserves.count).to eq(2)
      expect(reserves.where(applied: true).count).to eq(1)
      expect(reserves.find_by(idempotency_key: "K-1").applied).to be(true)
      expect(reserves.find_by(idempotency_key: "K-2").applied).to be(false)
    end

    it "gives each merchant its own replay row when both derive the same key" do
      other = Merchant.create!(
        name: "Other", code: "BIN-2", cutoff_hour: 14,
        principal_id: "cccccccc-0000-0000-0000-000000000000"
      )
      reserve(quantity: 3)

      res = reserve(quantity: 3, principal_id: other.principal_id)

      expect(res.success).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(6)
      expect(StockOperation.pluck(:idempotency_key)).to eq([ "reserve:ORD-1:SKU-1" ] * 2)
      expect(StockOperation.pluck(:merchant_id)).to contain_exactly(merchant.id, other.id)
    end

    it "still refuses one merchant's own key reused for a different request" do
      reserve(quantity: 3, key: "K-1")

      res = reserve(quantity: 8, key: "K-1")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("IDEMPOTENCY_KEY_CONFLICT")
      expect(inventory.reload.reserved_quantity).to eq(3)
    end
  end

  describe "#release_stock" do
    it "gives the stock back to the bin the reserve took it from" do
      reserve(quantity: 3)
      res = release

      expect(res.success).to be(true)
      expect(res.already_released).to be(false)
      expect(res.remaining_available).to eq(10)
      expect(inventory.reload.reserved_quantity).to eq(0)
      expect(StockReservation.first.released_at).to be_present
    end

    it "never credits a guessed bin at a live hold's expense" do
      low = WarehouseBin.create!(bin_code: "B-01", zone: "B", shelf_level: 1)
      first = BinInventory.create!(
        warehouse_bin: low, sku: "SKU-LEGACY", quantity: 10, reserved_quantity: 0
      )
      high = WarehouseBin.create!(bin_code: "B-02", zone: "B", shelf_level: 1)
      second = BinInventory.create!(
        warehouse_bin: high, sku: "SKU-LEGACY", quantity: 10, reserved_quantity: 0
      )

      live = reserve(quantity: 6, sku: "SKU-LEGACY", order_number: "ORD-LIVE")
      expect(live.success).to be(true)
      expect(first.reload.reserved_quantity).to eq(6)

      second.update!(reserved_quantity: 4)
      legacy = StockReservation.create!(
        merchant: merchant, order_number: "ORD-LEGACY", sku: "SKU-LEGACY", quantity: 4
      )
      legacy.update_column(:bin_inventory_id, nil)

      res = release(sku: "SKU-LEGACY", order_number: "ORD-LEGACY")

      expect(res.success).to be(true)
      expect(first.reload.reserved_quantity).to eq(6)
      expect(second.reload.reserved_quantity).to eq(4)
      expect(legacy.reload.released_at).to be_present
      expect(StockReservation.held.where(bin_inventory_id: second.id).sum(:quantity)).to eq(0)
    end

    it "credits a guessed bin the units that no live hold on it claims" do
      legacy = StockReservation.create!(
        merchant: merchant, order_number: "ORD-LEGACY-2", sku: "SKU-1", quantity: 3
      )
      legacy.update_column(:bin_inventory_id, nil)
      inventory.update!(reserved_quantity: 3)

      res = release(sku: "SKU-1", order_number: "ORD-LEGACY-2")

      expect(res.success).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(0)
      expect(legacy.reload.released_at).to be_present
    end

    it "credits the same bin the reserve debited when two bins carry one sku" do
      empty = WarehouseBin.create!(bin_code: "A-00", zone: "A", shelf_level: 1)
      low = BinInventory.create!(
        warehouse_bin: empty, sku: "SKU-2", quantity: 1, reserved_quantity: 0
      )
      stocked = WarehouseBin.create!(bin_code: "Z-99", zone: "Z", shelf_level: 1)
      full = BinInventory.create!(
        warehouse_bin: stocked, sku: "SKU-2", quantity: 50, reserved_quantity: 0
      )

      reserve(quantity: 5, sku: "SKU-2")
      release(sku: "SKU-2")

      expect(full.reload.reserved_quantity).to eq(0)
      expect(low.reload.reserved_quantity).to eq(0)
    end

    it "replays the original reply when the same key arrives twice" do
      reserve(quantity: 3)
      first = release
      second = release

      expect(second.to_proto).to eq(first.to_proto)
      expect(inventory.reload.reserved_quantity).to eq(0)
      expect(StockOperation.where(operation: StockOperation::RELEASE).count).to eq(1)
    end

    it "reports already_released for a second release arriving under a different key" do
      reserve(quantity: 3)
      release(key: "R-1")
      res = release(key: "R-2")

      expect(res.success).to be(true)
      expect(res.already_released).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "tombstones a release for stock that was never reserved" do
      res = release(order_number: "ORD-GHOST")

      expect(res.success).to be(true)
      expect(res.already_released).to be(true)

      tombstone = StockReservation.find_by(order_number: "ORD-GHOST", sku: "SKU-1")
      expect(tombstone.quantity).to eq(0)
      expect(tombstone.released_at).to be_present
    end

    it "makes a reserve arriving after that tombstone terminal" do
      release(order_number: "ORD-GHOST")

      res = reserve(order_number: "ORD-GHOST")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("STOCK_RESERVATION_RELEASED")
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "cannot release, and cannot poison, another merchant's pair" do
      other = Merchant.create!(
        name: "Other", code: "BIN-2", cutoff_hour: 14,
        principal_id: "cccccccc-0000-0000-0000-000000000000"
      )
      reserve(quantity: 3)

      res = release(principal_id: other.principal_id)

      expect(res.success).to be(true)
      expect(res.already_released).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(3)

      mine = StockReservation.find_by(merchant_id: merchant.id, order_number: "ORD-1")
      expect(mine.released_at).to be_nil
      expect(mine.quantity).to eq(3)

      theirs = StockReservation.find_by(merchant_id: other.id, order_number: "ORD-1")
      expect(theirs.quantity).to eq(0)
      expect(theirs.released_at).to be_present

      mine_released = release
      expect(mine_released.success).to be(true)
      expect(mine_released.already_released).to be(false)
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "still lets a merchant reserve a pair another merchant has already tombstoned" do
      other = Merchant.create!(
        name: "Other", code: "BIN-2", cutoff_hour: 14,
        principal_id: "cccccccc-0000-0000-0000-000000000000"
      )
      release(order_number: "ORD-CROSS", principal_id: other.principal_id)

      res = reserve(quantity: 3, order_number: "ORD-CROSS")

      expect(res.success).to be(true)
      expect(inventory.reload.reserved_quantity).to eq(3)
    end

    it "ignores the quantity on the request and gives back what the ledger says" do
      reserve(quantity: 3)
      release(quantity: 999, key: "R-1")

      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "refuses a request with no order number" do
      res = release(order_number: "")

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("INVALID_ARGUMENT")
      expect(StockReservation.count).to eq(0)
    end

    it "marks only the release that credited the counter as applied" do
      reserve(quantity: 3)
      release(key: "R-1")
      release(key: "R-2")

      releases = StockOperation.where(operation: StockOperation::RELEASE)
      expect(releases.count).to eq(2)
      expect(releases.find_by(idempotency_key: "R-1").applied).to be(true)
      expect(releases.find_by(idempotency_key: "R-2").applied).to be(false)
    end

    it "does not mark a tombstone as applied, because it credited nothing" do
      release(order_number: "ORD-GHOST")

      expect(StockOperation.where(operation: StockOperation::RELEASE).first.applied).to be(false)
    end

    it "releases a reservation whose bin has since been retired" do
      reserve(quantity: 3)
      bin.destroy!

      res = release

      expect(res.success).to be(true)
      expect(StockReservation.first.released_at).to be_present
    end
  end

  describe "#check_bin_stock" do
    it "reports the bin holding the sku" do
      inventory.update!(reserved_quantity: 4)

      res = handler.check_bin_stock(
        Fulfillment::V1::CheckBinStockRequest.new(
          merchant_principal_id: principal, sku: "SKU-1"
        ), nil
      )

      expect(res.found).to be(true)
      expect(res.physical_stock).to eq(10)
      expect(res.allocated_stock).to eq(4)
      expect(res.available_stock).to eq(6)
      expect(res.bin_location).to eq("A-01")
    end
  end
end
