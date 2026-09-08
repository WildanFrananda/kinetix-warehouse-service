# frozen_string_literal: true

class ScopeStockOperationKeysToMerchant < ActiveRecord::Migration[8.0]
  def up
    add_index :stock_operations, %i[merchant_id operation idempotency_key], unique: true,
              name: "index_stock_operations_on_merchant_operation_and_key"
    remove_index :stock_operations, name: "index_stock_operations_on_operation_and_key"
  end

  def down
    add_index :stock_operations, %i[operation idempotency_key], unique: true,
              name: "index_stock_operations_on_operation_and_key"
    remove_index :stock_operations, name: "index_stock_operations_on_merchant_operation_and_key"
  end
end
