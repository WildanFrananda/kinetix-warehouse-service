# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::IdempotentOperation do
  let!(:merchant) do
    Merchant.create!(
      name: "Gate Merchant", code: "GATE-1", cutoff_hour: 14,
      principal_id: "eeeeeeee-1111-2222-3333-444444444444"
    )
  end

  def gate(operation: StockOperation::RESERVE, key: "K-1")
    described_class.new(
      operation: operation, key: key, digest: StockOperation.digest_of([ operation, key ]),
      merchant: merchant, order_number: "ORD-G", sku: "SKU-G", quantity: 2
    )
  end

  def success_step
    Inventory::StepOutcome.new(
      message: Fulfillment::V1::ReserveStockResponse.new(
        success: true, bin_location: "G-01", remaining_available: 8
      ),
      commit: true,
      applied: true
    )
  end

  describe "the wait, and what it is derived from" do
    it "defaults longer than the deadline it assumes the caller uses" do
      expect(described_class::DEFAULT_LOCK_TIMEOUT_SECONDS)
        .to be > described_class::ASSUMED_CALLER_DEADLINE_SECONDS
    end

    it "clamps a configured value into the documented range" do
      with_lock_timeout("0") { expect(described_class.lock_timeout_ms).to eq(1_000) }
      with_lock_timeout("9999") { expect(described_class.lock_timeout_ms).to eq(120_000) }
      with_lock_timeout("30") { expect(described_class.lock_timeout_ms).to eq(30_000) }
    end

    it "uses the default when nothing is configured" do
      with_lock_timeout(nil) do
        expect(described_class.lock_timeout_ms)
          .to eq(described_class::DEFAULT_LOCK_TIMEOUT_SECONDS * 1_000)
      end
    end

    def with_lock_timeout(value)
      previous = ENV["WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS"]
      if value.nil?
        ENV.delete("WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS")
      else
        ENV["WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS"] = value
      end
      yield
    ensure
      ENV["WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS"] = previous
      ENV.delete("WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS") if previous.nil?
    end
  end

  describe "which wait ran out" do
    it "says RESERVATION_IN_PROGRESS when the claim insert itself timed out" do
      allow(StockOperation).to receive(:create!).and_raise(ActiveRecord::LockWaitTimeout)

      result = gate.call { success_step }

      expect(result.status).to eq(Inventory::OperationOutcome::RETRY_LATER)
      expect(result.message.success).to be(false)
      expect(result.message.error.error_code).to eq("RESERVATION_IN_PROGRESS")
      expect(result.message.error.message).to include("identical request")
    end

    it "says STOCK_LOCK_TIMEOUT when the wait was inside the work, not on the claim" do
      result = gate.call { raise ActiveRecord::LockWaitTimeout }

      expect(result.status).to eq(Inventory::OperationOutcome::RETRY_LATER)
      expect(result.message.error.error_code).to eq("STOCK_LOCK_TIMEOUT")
      expect(result.message.error.message).to include("another order")
      expect(result.message.error.message).not_to include("identical request")
    end

    it "keeps nothing behind when the work times out" do
      gate.call { raise ActiveRecord::LockWaitTimeout }

      expect(StockOperation.count).to eq(0)
      expect(StockReservation.count).to eq(0)
    end

    it "still answers RESERVATION_IN_PROGRESS when the replay read itself times out" do
      allow(StockOperation).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
      allow(StockOperation).to receive(:lock).and_raise(ActiveRecord::LockWaitTimeout)

      result = gate.call { success_step }

      expect(result.status).to eq(Inventory::OperationOutcome::RETRY_LATER)
      expect(result.message.error.error_code).to eq("RESERVATION_IN_PROGRESS")
    end
  end
end
