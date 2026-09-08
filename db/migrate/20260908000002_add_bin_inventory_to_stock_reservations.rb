# frozen_string_literal: true

class AddBinInventoryToStockReservations < ActiveRecord::Migration[8.0]
  def change
    add_reference :stock_reservations, :bin_inventory, null: true, foreign_key: false
  end
end
