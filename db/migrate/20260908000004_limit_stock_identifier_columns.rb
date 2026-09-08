# frozen_string_literal: true

class LimitStockIdentifierColumns < ActiveRecord::Migration[8.0]
  ORDER_NUMBER_LIMIT = 64
  SKU_LIMIT = 128

  def up
    change_column :stock_operations, :order_number, :string, limit: ORDER_NUMBER_LIMIT, null: false
    change_column :stock_operations, :sku, :string, limit: SKU_LIMIT, null: false
    change_column :stock_reservations, :order_number, :string,
                  limit: ORDER_NUMBER_LIMIT, null: false
    change_column :stock_reservations, :sku, :string, limit: SKU_LIMIT, null: false
  end

  def down
    change_column :stock_operations, :order_number, :string, limit: nil, null: false
    change_column :stock_operations, :sku, :string, limit: nil, null: false
    change_column :stock_reservations, :order_number, :string, limit: nil, null: false
    change_column :stock_reservations, :sku, :string, limit: nil, null: false
  end
end
