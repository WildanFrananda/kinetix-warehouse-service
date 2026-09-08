# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StockOperation do
  {
    "stock_operations" => described_class,
    "stock_reservations" => StockReservation
  }.each do |table, model|
    it "keeps #{table}.order_number at MAX_ORDER_NUMBER_LENGTH" do
      expect(model.columns_hash["order_number"].limit)
        .to eq(StockOperation::MAX_ORDER_NUMBER_LENGTH)
    end

    it "keeps #{table}.sku at MAX_SKU_LENGTH" do
      expect(model.columns_hash["sku"].limit).to eq(StockOperation::MAX_SKU_LENGTH)
    end
  end

  it "keeps stock_operations.idempotency_key at MAX_KEY_LENGTH" do
    expect(described_class.columns_hash["idempotency_key"].limit)
      .to eq(StockOperation::MAX_KEY_LENGTH)
  end

  it "leaves room for a derived key at the maximum identifier lengths" do
    # The derived key is "#{operation}:#{order_number}:#{sku}". If that could exceed
    # MAX_KEY_LENGTH, a caller sending no key at all would be refused with a message naming
    # idempotency_key — blaming a field it never populated, which is the bug this bound removes.
    longest = [
      StockOperation::RELEASE,
      "O" * StockOperation::MAX_ORDER_NUMBER_LENGTH,
      "S" * StockOperation::MAX_SKU_LENGTH
    ].join(":")

    expect(longest.length).to be <= StockOperation::MAX_KEY_LENGTH
  end
end
