# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::AdjustStockService do
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  let(:owner) { "22222222-3333-4444-5555-666666666666" }
  let(:staff) { "11111111-2222-3333-4444-555555555555" }

  let!(:inventory) do
    BinInventory.create!(
      warehouse_bin: bin, sku: "SKU-1", quantity: 10, reserved_quantity: 0,
      merchant_principal_id: owner
    )
  end

  def adjust(delta: -1, reason: StockAdjustment::DAMAGE, key: "ADJ-1", sku: "SKU-1",
             bin_code: "A-01-1", merchant: nil, note: nil)
    described_class.new(
      bin_code: bin_code,
      sku: sku,
      quantity_delta: delta,
      reason: reason,
      idempotency_key: key,
      adjusted_by_principal_id: staff,
      merchant_principal_id: merchant || owner,
      note: note
    ).call
  end

  it "writes damaged goods off the shelf" do
    result = adjust(delta: -3, reason: StockAdjustment::DAMAGE, note: "crushed in transit")

    expect(result.error).to be_nil
    expect(result.quantity_on_hand).to eq(7)
    expect(inventory.reload.quantity).to eq(7)
  end

  it "books a count that found more than the system said" do
    result = adjust(delta: 2, reason: StockAdjustment::MISCOUNT)

    expect(result.error).to be_nil
    expect(inventory.reload.quantity).to eq(12)
  end

  it "records what the shelf held before and after, and who said so" do
    adjust(delta: -4, reason: StockAdjustment::SHRINKAGE, key: "ADJ-S")

    row = StockAdjustment.find_by(idempotency_key: "ADJ-S")
    expect(row.quantity_before).to eq(10)
    expect(row.quantity_after).to eq(6)
    expect(row.quantity_delta).to eq(-4)
    expect(row.reason).to eq(StockAdjustment::SHRINKAGE)
    expect(row.adjusted_by_principal_id).to eq(staff)
    expect(row.merchant_principal_id).to eq(owner)
  end

  it "refuses a reduction that would cut into stock reserved for orders" do
    inventory.update!(reserved_quantity: 8)

    result = adjust(delta: -5, reason: StockAdjustment::DAMAGE)

    expect(result.error).to eq(described_class::WOULD_CUT_RESERVED)
    expect(result.quantity_on_hand).to eq(10)
    expect(result.reserved_quantity).to eq(8)
    expect(inventory.reload.quantity).to eq(10)
    expect(StockAdjustment.count).to eq(0)
  end

  it "allows a reduction down to exactly the reserved figure" do
    inventory.update!(reserved_quantity: 8)

    result = adjust(delta: -2, reason: StockAdjustment::DAMAGE)

    expect(result.error).to be_nil
    expect(inventory.reload.quantity).to eq(8)
    expect(inventory.available_quantity).to eq(0)
  end

  it "applies a repeated key once, however many times it is sent" do
    first = adjust(delta: -3, key: "SAME")
    second = adjust(delta: -3, key: "SAME")
    third = adjust(delta: -3, key: "SAME")

    expect(first.replayed).to be(false)
    expect(second.replayed).to be(true)
    expect(third.replayed).to be(true)
    expect(inventory.reload.quantity).to eq(7)
    expect(StockAdjustment.where(idempotency_key: "SAME").count).to eq(1)
  end

  it "refuses to adjust another merchant's goods" do
    result = adjust(delta: -3, merchant: "99999999-9999-9999-9999-999999999999")

    expect(result.error).to eq(described_class::WRONG_OWNER)
    expect(inventory.reload.quantity).to eq(10)
    expect(StockAdjustment.count).to eq(0)
  end

  it "refuses stock with no owner rather than adopting one, unlike a receipt" do
    inventory.update!(merchant_principal_id: nil)

    result = adjust(delta: -3)

    expect(result.error).to eq(described_class::STOCK_HAS_NO_OWNER)
    expect(inventory.reload.quantity).to eq(10)
  end

  it "refuses a reason it does not know" do
    result = adjust(delta: -3, reason: "BECAUSE")

    expect(result.error).to eq(described_class::UNKNOWN_REASON)
    expect(StockAdjustment.count).to eq(0)
  end

  it "refuses a delta of zero, which records nothing and changes nothing" do
    expect(adjust(delta: 0).error).to eq(described_class::INVALID_DELTA)
    expect(StockAdjustment.count).to eq(0)
  end

  it "refuses a sku that is not on that shelf rather than creating the row" do
    result = adjust(delta: -1, sku: "SKU-ABSENT")

    expect(result.error).to eq(described_class::STOCK_NOT_FOUND)
    expect(BinInventory.where(sku: "SKU-ABSENT").count).to eq(0)
  end

  it "refuses a bin that does not exist" do
    result = adjust(delta: -1, bin_code: "NO-SUCH-BIN")

    expect(result.error).to eq(described_class::BIN_NOT_FOUND)
  end

  it "leaves the reserved figure untouched, so an adjustment never frees a reservation" do
    inventory.update!(reserved_quantity: 4)

    adjust(delta: -2, reason: StockAdjustment::EXPIRY)

    inventory.reload
    expect(inventory.quantity).to eq(8)
    expect(inventory.reserved_quantity).to eq(4)
    expect(inventory.available_quantity).to eq(4)
  end
end
