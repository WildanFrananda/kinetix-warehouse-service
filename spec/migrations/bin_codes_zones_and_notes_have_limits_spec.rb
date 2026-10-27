# typed: ignore
# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261022184035_bin_codes_zones_and_notes_have_limits").to_s

RSpec.describe BinCodesZonesAndNotesHaveLimits do
  include_context "a migration runs inside each example"

  let(:connection) { ActiveRecord::Base.connection }
  let(:staff) { "aaaaaaaa-3333-4333-8444-555555555555" }
  let(:owner) { "bbbbbbbb-3333-4333-8444-555555555555" }

  before { run(:down) }

  def run(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def limit(table, column)
    connection.columns(table).find { |candidate| candidate.name == column.to_s }.limit
  end

  def limits
    {
      bin_code: limit(:warehouse_bins, :bin_code),
      zone: limit(:warehouse_bins, :zone),
      receipt_note: limit(:stock_receipts, :note),
      adjustment_note: limit(:stock_adjustments, :note)
    }
  end

  def bin(code:, zone: "A")
    WarehouseBin.insert_all(
      [ { bin_code: code, zone: zone, shelf_level: 1, created_at: Time.current, updated_at: Time.current } ],
      returning: %i[id]
    ).first["id"]
  end

  def receipt(bin_id, note)
    StockReceipt.insert_all(
      [
        {
          warehouse_bin_id: bin_id,
          sku: "SKU-1",
          quantity: 1,
          idempotency_key: SecureRandom.uuid,
          received_by_principal_id: staff,
          merchant_principal_id: owner,
          note: note,
          created_at: Time.current,
          updated_at: Time.current
        }
      ],
      returning: %i[id]
    ).first["id"]
  end

  it "limits the columns when every row fits, keeping what they hold" do
    bin_id = bin(code: "B" * 64, zone: "Z" * 64)
    receipt_id = receipt(bin_id, "n" * 1000)

    run(:up)

    expect(limits).to eq(bin_code: 64, zone: 64, receipt_note: 1000, adjustment_note: 1000)
    expect(WarehouseBin.find(bin_id).bin_code).to eq("B" * 64)
    expect(StockReceipt.find(receipt_id).note).to eq("n" * 1000)
  end

  it "refuses, naming the rows and their lengths, rather than cutting a value short" do
    long_code = bin(code: "C" * 70)
    long_zone = bin(code: "Z-1", zone: "Z" * 65)
    long_note = receipt(long_code, "n" * 1200)

    expect { run(:up) }.to raise_error do |error|
      expect(error.message).to include("warehouse_bins.bin_code over 64 characters: id #{long_code} (70)")
      expect(error.message).to include("warehouse_bins.zone over 64 characters: id #{long_zone} (65)")
      expect(error.message).to include("stock_receipts.note over 1000 characters: id #{long_note} (1200)")
      expect(error.message).not_to include("stock_adjustments.note")
    end

    expect(limits).to eq(bin_code: nil, zone: nil, receipt_note: nil, adjustment_note: nil)
    expect(WarehouseBin.find(long_code).bin_code).to eq("C" * 70)
  end

  it "gives the columns back their old unlimited type on the way down" do
    run(:up)
    run(:down)

    expect(limits).to eq(bin_code: nil, zone: nil, receipt_note: nil, adjustment_note: nil)
    expect(connection.columns(:warehouse_bins).find { |column| column.name == "bin_code" }.null).to be(false)
  end
end
