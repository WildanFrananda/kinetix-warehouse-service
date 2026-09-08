# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::AbandonedHoldReport do
  let!(:merchant) do
    Merchant.create!(
      name: "Hold Merchant", code: "HOLD-1", cutoff_hour: 14,
      principal_id: "ffffffff-1111-2222-3333-444444444444"
    )
  end

  let!(:bin) { WarehouseBin.create!(bin_code: "H-01", zone: "H", shelf_level: 1) }
  let!(:inventory) do
    BinInventory.create!(warehouse_bin: bin, sku: "SKU-H", quantity: 20, reserved_quantity: 0)
  end

  def hold(order_number:, age_hours:, quantity: 3, released_at: nil)
    StockReservation.create!(
      merchant: merchant, order_number: order_number, sku: "SKU-H", quantity: quantity,
      bin_inventory: inventory, released_at: released_at
    ).tap { |row| row.update_column(:created_at, age_hours.hours.ago) }
  end

  it "names a hold older than the threshold" do
    old = hold(order_number: "ORD-OLD", age_hours: 30)

    expect(described_class.new.rows.map(&:id)).to eq([ old.id ])
  end

  it "ignores a hold young enough that its owner may still be working" do
    hold(order_number: "ORD-YOUNG", age_hours: 2)

    expect(described_class.new.rows).to be_empty
  end

  it "ignores a released row, tombstones included" do
    hold(order_number: "ORD-DONE", age_hours: 30, released_at: 29.hours.ago)
    hold(order_number: "ORD-GHOST", age_hours: 30, quantity: 0, released_at: 30.hours.ago)

    expect(described_class.new.rows).to be_empty
  end

  it "reports the units frozen, not just the row count" do
    hold(order_number: "ORD-A", age_hours: 30, quantity: 3)
    hold(order_number: "ORD-B", age_hours: 40, quantity: 4)

    report = described_class.new

    expect(report.rows.size).to eq(2)
    expect(report.units).to eq(7)
  end

  it "takes the threshold from the environment, clamped" do
    hold(order_number: "ORD-MID", age_hours: 5)

    expect(described_class.new(older_than_hours: 24).rows).to be_empty
    expect(described_class.new(older_than_hours: 4).rows.size).to eq(1)

    previous = ENV["WAREHOUSE_ABANDONED_HOLD_HOURS"]
    begin
      ENV["WAREHOUSE_ABANDONED_HOLD_HOURS"] = "0"
      expect(described_class.age_hours).to eq(described_class::MIN_AGE_HOURS)
      ENV["WAREHOUSE_ABANDONED_HOLD_HOURS"] = "4"
      expect(described_class.age_hours).to eq(4)
    ensure
      previous.nil? ? ENV.delete("WAREHOUSE_ABANDONED_HOLD_HOURS") : ENV["WAREHOUSE_ABANDONED_HOLD_HOURS"] = previous
    end
  end

  it "logs one alertable anchor per hold, plus a summary" do
    row = hold(order_number: "ORD-OLD", age_hours: 30)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:info)

    expect(described_class.new.call).to eq(1)

    expect(Rails.logger).to have_received(:error)
      .with(/stock\.idem abandoned_hold reservation_id=#{row.id} .*order_number=ORD-OLD/)
    expect(Rails.logger).to have_received(:error)
      .with(/stock\.idem abandoned_hold_summary count=1 units=3/)
  end

  it "says at INFO that it ran and found nothing, so silence means it did not run" do
    allow(Rails.logger).to receive(:info)

    expect(described_class.new.call).to eq(0)

    expect(Rails.logger).to have_received(:info)
      .with(/stock\.idem abandoned_hold_summary count=0 units=0/)
  end

  it "changes nothing — it is a report, not a reaper" do
    row = hold(order_number: "ORD-OLD", age_hours: 30)
    inventory.update!(reserved_quantity: 3)

    described_class.new.call

    expect(row.reload.released_at).to be_nil
    expect(inventory.reload.reserved_quantity).to eq(3)
    expect(StockReservation.count).to eq(1)
  end

  describe ReportAbandonedHoldsJob do
    it "runs the same report and writes nothing" do
      hold(order_number: "ORD-OLD", age_hours: 30)
      allow(Rails.logger).to receive(:error)

      described_class.perform_now

      expect(Rails.logger).to have_received(:error).with(/stock\.idem abandoned_hold /)
      expect(StockReservation.held.count).to eq(1)
    end
  end
end
