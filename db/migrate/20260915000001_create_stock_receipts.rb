# typed: strict
# frozen_string_literal: true

class CreateStockReceipts < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_receipts do |t|
      t.references :warehouse_bin, null: false, foreign_key: true
      t.string :sku, null: false
      t.integer :quantity, null: false
      t.string :idempotency_key, limit: 255, null: false
      t.uuid :received_by_principal_id, null: false
      t.string :note

      t.timestamps
    end

    add_index :stock_receipts, :idempotency_key, unique: true
    add_index :stock_receipts, :sku
    add_check_constraint :stock_receipts, "quantity > 0", name: "stock_receipts_quantity_positive"
  end
end
