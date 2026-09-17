# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::ReceiveStockService do
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  def receive(quantity: 5, key: "RCV-1", sku: "SKU-1", bin_code: "A-01-1")
    described_class.new(
      bin_code: bin_code,
      sku: sku,
      quantity: quantity,
      idempotency_key: key,
      received_by_principal_id: "11111111-2222-3333-4444-555555555555"
    ).call
  end

  it "creates the inventory row on the first delivery of a sku" do
    expect(BinInventory.find_by(sku: "SKU-1")).to be_nil

    result = receive(quantity: 5)

    expect(result.error).to be_nil
    expect(result.quantity_on_hand).to eq(5)
    expect(BinInventory.find_by(warehouse_bin: bin, sku: "SKU-1").quantity).to eq(5)
  end

  it "adds to what is already on the shelf rather than replacing it" do
    receive(quantity: 5, key: "RCV-1")
    result = receive(quantity: 3, key: "RCV-2")

    expect(result.quantity_on_hand).to eq(8)
  end

  it "records who booked it in and how much" do
    receive(quantity: 7, key: "RCV-7")

    receipt = StockReceipt.find_by(idempotency_key: "RCV-7")
    expect(receipt.quantity).to eq(7)
    expect(receipt.sku).to eq("SKU-1")
    expect(receipt.received_by_principal_id).to eq("11111111-2222-3333-4444-555555555555")
    expect(receipt.warehouse_bin_id).to eq(bin.id)
  end

  it "books a repeated key once, however many times it is sent" do
    first = receive(quantity: 5, key: "SAME")
    second = receive(quantity: 5, key: "SAME")
    third = receive(quantity: 5, key: "SAME")

    expect(first.replayed).to be(false)
    expect(second.replayed).to be(true)
    expect(third.replayed).to be(true)
    expect(second.quantity_on_hand).to eq(5)
    expect(BinInventory.find_by(sku: "SKU-1").quantity).to eq(5)
    expect(StockReceipt.where(idempotency_key: "SAME").count).to eq(1)
  end

  it "refuses a bin that does not exist rather than inventing a shelf" do
    result = receive(bin_code: "NO-SUCH-BIN")

    expect(result.error).to eq(described_class::BIN_NOT_FOUND)
    expect(StockReceipt.count).to eq(0)
    expect(BinInventory.count).to eq(0)
  end

  it "refuses a quantity that is not a delivery" do
    expect(receive(quantity: 0).error).to eq(described_class::INVALID_QUANTITY)
    expect(receive(quantity: -3).error).to eq(described_class::INVALID_QUANTITY)
    expect(StockReceipt.count).to eq(0)
  end

  it "leaves reserved quantity alone, so receiving never releases somebody's reservation" do
    receive(quantity: 10, key: "RCV-A")
    inventory = BinInventory.find_by(sku: "SKU-1")
    inventory.update!(reserved_quantity: 4)

    receive(quantity: 5, key: "RCV-B")

    inventory.reload
    expect(inventory.quantity).to eq(15)
    expect(inventory.reserved_quantity).to eq(4)
    expect(inventory.available_quantity).to eq(11)
  end
end
