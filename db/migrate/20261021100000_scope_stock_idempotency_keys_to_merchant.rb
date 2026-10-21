# typed: strict
# frozen_string_literal: true

class ScopeStockIdempotencyKeysToMerchant < ActiveRecord::Migration[8.1]
  def up
    add_index :stock_receipts,
              %i[merchant_principal_id idempotency_key],
              unique: true,
              nulls_not_distinct: true,
              name: "index_stock_receipts_on_merchant_and_idempotency_key",
              if_not_exists: true
    remove_index :stock_receipts, name: "index_stock_receipts_on_idempotency_key", if_exists: true

    add_index :stock_adjustments,
              %i[merchant_principal_id idempotency_key],
              unique: true,
              name: "index_stock_adjustments_on_merchant_and_idempotency_key",
              if_not_exists: true
    remove_index :stock_adjustments, name: "index_stock_adjustments_on_idempotency_key", if_exists: true
  end

  def down
    add_index :stock_adjustments,
              :idempotency_key,
              unique: true,
              name: "index_stock_adjustments_on_idempotency_key",
              if_not_exists: true
    remove_index :stock_adjustments, name: "index_stock_adjustments_on_merchant_and_idempotency_key", if_exists: true

    add_index :stock_receipts,
              :idempotency_key,
              unique: true,
              name: "index_stock_receipts_on_idempotency_key",
              if_not_exists: true
    remove_index :stock_receipts, name: "index_stock_receipts_on_merchant_and_idempotency_key", if_exists: true
  end
end
