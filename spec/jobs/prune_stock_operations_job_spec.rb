# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe PruneStockOperationsJob do
  let(:merchant) do
    Merchant.create!(
      name: "Prune Merchant", code: "PRUNE-1", cutoff_hour: 14,
      principal_id: "eeeeeeee-1111-2222-3333-444444444444"
    )
  end

  def operation(created_at:, conflict_count: 0, key:)
    StockOperation.create!(
      operation: StockOperation::RESERVE, idempotency_key: key,
      request_digest: "d" * 64, merchant: merchant, order_number: "ORD-P", sku: "SKU-P",
      quantity: 1, response: "", conflict_count: conflict_count, created_at: created_at
    )
  end

  it "drops replay records past the retention window" do
    stale = operation(key: "old", created_at: 8.days.ago)
    fresh = operation(key: "new", created_at: 1.day.ago)

    described_class.perform_now

    expect(StockOperation.exists?(stale.id)).to be(false)
    expect(StockOperation.exists?(fresh.id)).to be(true)
  end

  it "keeps a record that ever saw a conflict, however old" do
    conflicted = operation(key: "bad", created_at: 90.days.ago, conflict_count: 2)

    described_class.perform_now

    expect(StockOperation.exists?(conflicted.id)).to be(true)
  end
end
