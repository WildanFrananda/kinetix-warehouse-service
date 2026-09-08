# typed: false
# frozen_string_literal: true

require "rails_helper"
require "rake"
require "fulfillment/v1/fulfillment_services_pb"
require_relative "../../app/rpc/bin_stock_service_handler"

RSpec.describe "stock rake tasks" do
  let(:handler) { Rpc::BinStockServiceHandler.new }
  let(:principal) { "abababab-1111-2222-3333-444444444444" }

  let!(:merchant) do
    Merchant.create!(name: "Rake Merchant", code: "RAKE-1", cutoff_hour: 14, principal_id: principal)
  end
  let!(:bin) { WarehouseBin.create!(bin_code: "R-01", zone: "R", shelf_level: 1) }
  let!(:inventory) do
    BinInventory.create!(warehouse_bin: bin, sku: "SKU-R", quantity: 10, reserved_quantity: 0)
  end

  before do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    %w[stock:abandoned_holds stock:release_hold].each { |name| Rake::Task[name].reenable }
  end

  def reserve(order_number: "ORD-R", quantity: 3)
    handler.reserve_stock(
      Fulfillment::V1::ReserveStockRequest.new(
        merchant_principal_id: principal, sku: "SKU-R", quantity: quantity,
        order_number: order_number
      ), nil
    )
  end

  def run(name, *args)
    original = $stdout
    $stdout = StringIO.new
    Rake::Task[name].invoke(*args)
    $stdout.string
  ensure
    $stdout = original
  end

  describe "stock:abandoned_holds" do
    it "prints nothing to act on when every hold is fresh" do
      reserve

      expect(run("stock:abandoned_holds")).to include("Nothing is stranded")
    end

    it "lists an old hold with the id the reclaim command takes" do
      reserve
      row = StockReservation.first
      row.update_column(:created_at, 30.hours.ago)

      output = run("stock:abandoned_holds")

      expect(output).to include("1 hold(s)", "3 unit(s) frozen", "ORD-R", row.id.to_s)
      expect(output).to include("stock:release_hold[ID]")
    end
  end

  describe "stock:release_hold" do
    it "credits the bin and closes the ledger row" do
      reserve
      row = StockReservation.first
      expect(inventory.reload.reserved_quantity).to eq(3)

      output = run("stock:release_hold", row.id.to_s)

      expect(output).to include("Released reservation #{row.id}")
      expect(inventory.reload.reserved_quantity).to eq(0)
      expect(row.reload.released_at).to be_present
    end

    it "keeps the row, so the pair stays terminal for a late reserve" do
      reserve
      row = StockReservation.first
      run("stock:release_hold", row.id.to_s)

      late = reserve

      expect(StockReservation.count).to eq(1)
      expect(late.success).to be(false)
      expect(late.error.error_code).to eq("STOCK_RESERVATION_RELEASED")
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "says a caller got there first instead of claiming the reclaim" do
      reserve
      row = StockReservation.first

      losing = Inventory::StepOutcome.new(
        message: Fulfillment::V1::ReleaseStockResponse.new(
          success: true, already_released: true, remaining_available: 10
        ),
        commit: true,
        applied: false
      )
      service = instance_double(Inventory::ReleaseStockService)
      allow(service).to receive(:call) do
        row.update!(released_at: Time.current)
        inventory.reload.update!(reserved_quantity: 0)
        losing
      end
      allow(Inventory::ReleaseStockService).to receive(:new).and_return(service)

      output = run("stock:release_hold", row.id.to_s)

      expect(output).to include("a caller got there first")
      expect(output).to include("Nothing was reclaimed by hand")
      expect(output).not_to include("Released reservation #{row.id}")
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "says plainly when it closed a row without putting any units back" do
      reserve
      row = StockReservation.first
      bin.destroy!

      output = run("stock:release_hold", row.id.to_s)

      expect(output).to include("WITHOUT crediting any counter")
      expect(output).to include("are NOT back")
      expect(row.reload.released_at).to be_present
    end

    it "refuses to act twice on the same row" do
      reserve
      row = StockReservation.first
      run("stock:release_hold", row.id.to_s)
      Rake::Task["stock:release_hold"].reenable

      expect { run("stock:release_hold", row.id.to_s) }.to raise_error(SystemExit)
      expect(inventory.reload.reserved_quantity).to eq(0)
    end

    it "refuses an id that names no row rather than inventing one" do
      expect { run("stock:release_hold", "999999") }.to raise_error(SystemExit)
      expect(StockReservation.count).to eq(0)
    end

    it "refuses to run with no id" do
      expect { run("stock:release_hold") }.to raise_error(SystemExit)
    end
  end
end
