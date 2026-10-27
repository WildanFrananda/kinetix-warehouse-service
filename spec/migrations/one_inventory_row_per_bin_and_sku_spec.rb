# typed: ignore
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261021100003_one_inventory_row_per_bin_and_sku").to_s

RSpec.describe OneInventoryRowPerBinAndSku do
  include_context "a migration runs inside each example"

  let(:connection) { ActiveRecord::Base.connection }
  let(:owner) { "aaaaaaaa-2222-4333-8444-555555555555" }
  let(:other) { "bbbbbbbb-2222-4333-8444-555555555555" }
  let!(:merchant) { Merchant.create!(principal_id: owner, cutoff_hour: 14) }
  let!(:bin) { WarehouseBin.create!(bin_code: "DUP-01", zone: "D", shelf_level: 1) }

  before { connection.remove_index :bin_inventories, name: described_class::INDEX }

  def row(quantity:, reserved:, owner_id:)
    BinInventory.create!(
      warehouse_bin: bin,
      sku: "SKU-DUP",
      quantity: quantity,
      reserved_quantity: reserved,
      merchant_principal_id: owner_id
    )
  end

  def migrate
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }
  end

  def unique_index?
    connection.indexes(:bin_inventories).any? { |index| index.name == described_class::INDEX && index.unique }
  end

  it "merges one owner's rows into the first, summing what they hold and moving their reservations" do
    first = row(quantity: 4, reserved: 1, owner_id: owner)
    second = row(quantity: 6, reserved: 2, owner_id: owner)
    held = StockReservation.create!(
      merchant: merchant,
      order_number: "ORD-DUP",
      sku: "SKU-DUP",
      quantity: 2,
      bin_inventory: second
    )

    migrate

    expect(BinInventory.where(warehouse_bin_id: bin.id, sku: "SKU-DUP").pluck(:id)).to eq([ first.id ])
    expect(first.reload.quantity).to eq(10)
    expect(first.reserved_quantity).to eq(3)
    expect(held.reload.bin_inventory_id).to eq(first.id)
    expect(unique_index?).to be(true)
  end

  it "merges rows that both have no owner recorded, which loses nothing" do
    first = row(quantity: 2, reserved: 0, owner_id: nil)
    row(quantity: 3, reserved: 0, owner_id: nil)

    migrate

    expect(BinInventory.where(warehouse_bin_id: bin.id, sku: "SKU-DUP").count).to eq(1)
    expect(first.reload.quantity).to eq(5)
  end

  it "refuses, naming the rows, when the rows disagree about whose goods they are" do
    first = row(quantity: 4, reserved: 0, owner_id: owner)
    second = row(quantity: 6, reserved: 0, owner_id: other)

    expect { migrate }.to raise_error(/bin_inventories\.id=\{#{first.id},#{second.id}\}.*#{other}/)
    expect(BinInventory.where(id: [ first.id, second.id ]).sum(:quantity)).to eq(10)
    expect(unique_index?).to be(false)
  end

  it "refuses when one row has an owner and the other has none" do
    row(quantity: 4, reserved: 0, owner_id: owner)
    row(quantity: 6, reserved: 0, owner_id: nil)

    expect { migrate }.to raise_error(/no owner/)
  end

  it "only adds the index when there is nothing to merge" do
    row(quantity: 4, reserved: 0, owner_id: owner)

    migrate

    expect(unique_index?).to be(true)
    expect(BinInventory.find_by(warehouse_bin_id: bin.id, sku: "SKU-DUP").quantity).to eq(4)
  end
end
