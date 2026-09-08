# frozen_string_literal: true

class AddReplayRefusedCountToStockOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :stock_operations, :replay_refused_count, :integer, null: false, default: 0
  end
end
