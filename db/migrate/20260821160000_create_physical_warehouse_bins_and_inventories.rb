# frozen_string_literal: true

class CreatePhysicalWarehouseBinsAndInventories < ActiveRecord::Migration[8.0]
  def change
    # Create Physical Warehouse Bins table
    create_table :warehouse_bins, if_not_exists: true do |t|
      t.string :bin_code, null: false
      t.string :zone, null: false
      t.integer :shelf_level, null: false, default: 1
      t.timestamps
    end
    add_index :warehouse_bins, :bin_code, unique: true, if_not_exists: true

    # Create Bin Inventories table
    create_table :bin_inventories, if_not_exists: true do |t|
      t.references :warehouse_bin, null: false, foreign_key: true
      t.string :sku, null: false
      t.integer :quantity, null: false, default: 0
      t.integer :reserved_quantity, null: false, default: 0
      t.timestamps
    end
    add_index :bin_inventories, :sku, if_not_exists: true
  end
end
