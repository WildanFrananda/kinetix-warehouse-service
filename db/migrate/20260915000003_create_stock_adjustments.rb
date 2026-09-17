# typed: strict
# frozen_string_literal: true

class CreateStockAdjustments < ActiveRecord::Migration[8.0]
  REASONS = %w[DAMAGE SHRINKAGE MISCOUNT RETURN_TO_SUPPLIER EXPIRY].freeze

  def change
    create_table :stock_adjustments do |t|
      t.references :warehouse_bin, null: false, foreign_key: true
      t.string :sku, null: false
      t.uuid :merchant_principal_id, null: false
      t.integer :quantity_delta, null: false
      t.string :reason, limit: 32, null: false
      t.string :note
      t.string :idempotency_key, limit: 255, null: false
      t.uuid :adjusted_by_principal_id, null: false
      t.integer :quantity_before, null: false
      t.integer :quantity_after, null: false

      t.timestamps
    end

    add_index :stock_adjustments, :idempotency_key, unique: true
    add_index :stock_adjustments, [ :sku, :created_at ]
    add_check_constraint :stock_adjustments, "quantity_delta <> 0",
                         name: "stock_adjustments_delta_not_zero"
    add_check_constraint :stock_adjustments,
                         "reason IN ('DAMAGE','SHRINKAGE','MISCOUNT','RETURN_TO_SUPPLIER','EXPIRY')",
                         name: "stock_adjustments_reason_known"
  end
end
