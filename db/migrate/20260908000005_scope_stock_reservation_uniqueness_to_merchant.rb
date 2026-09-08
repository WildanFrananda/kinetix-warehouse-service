# frozen_string_literal: true

class ScopeStockReservationUniquenessToMerchant < ActiveRecord::Migration[8.0]
  def up
    add_index :stock_reservations, %i[merchant_id order_number sku], unique: true,
              name: "index_stock_reservations_on_merchant_order_and_sku"
    remove_index :stock_reservations, name: "index_stock_reservations_on_order_and_sku"
  end

  def down
    add_index :stock_reservations, %i[order_number sku], unique: true,
              name: "index_stock_reservations_on_order_and_sku"
    remove_index :stock_reservations, name: "index_stock_reservations_on_merchant_order_and_sku"
  end
end
