# frozen_string_literal: true

class CreateStockOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_operations do |t|
      t.string :operation, null: false, limit: 16
      t.string :idempotency_key, null: false, limit: 255
      t.string :request_digest, null: false, limit: 64
      t.references :merchant, null: false, foreign_key: true
      t.string :order_number, null: false
      t.string :sku, null: false
      t.integer :quantity, null: false
      t.binary :response, null: false
      t.boolean :applied, null: false, default: false
      t.string :first_request_id, null: false, default: ""
      t.string :last_replay_request_id
      t.integer :replay_count, null: false, default: 0
      t.integer :conflict_count, null: false, default: 0

      t.timestamps
    end

    add_index :stock_operations, %i[operation idempotency_key], unique: true,
              name: "index_stock_operations_on_operation_and_key"
    add_index :stock_operations, :created_at, name: "index_stock_operations_on_created_at"
    add_index :stock_operations, :order_number, name: "index_stock_operations_on_order_number"
  end
end
