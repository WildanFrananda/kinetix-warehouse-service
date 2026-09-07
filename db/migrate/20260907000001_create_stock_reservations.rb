# frozen_string_literal: true

class CreateStockReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_reservations do |t|
      t.string :order_number, null: false
      t.string :sku, null: false
      t.integer :quantity, null: false
      t.references :merchant, null: false, foreign_key: true
      t.datetime :released_at

      t.timestamps
    end

    add_index :stock_reservations, %i[order_number sku], unique: true,
              name: "index_stock_reservations_on_order_and_sku"
    add_index :stock_reservations, :sku
  end
end
