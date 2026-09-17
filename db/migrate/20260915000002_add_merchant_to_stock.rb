# typed: strict
# frozen_string_literal: true

class AddMerchantToStock < ActiveRecord::Migration[8.0]
  def change
    add_column :bin_inventories, :merchant_principal_id, :uuid
    add_column :stock_receipts, :merchant_principal_id, :uuid

    add_index :bin_inventories, [ :merchant_principal_id, :sku ]
  end
end
