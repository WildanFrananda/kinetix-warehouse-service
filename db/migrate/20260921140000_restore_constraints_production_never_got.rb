# typed: strict
# frozen_string_literal: true

class RestoreConstraintsProductionNeverGot < ActiveRecord::Migration[8.0]
  INDEXES = [
    [ :shipping_labels, :awb_number, { unique: true } ],
    [ :fulfillment_tasks, [ :merchant_id, :order_number ], { unique: true } ],
    [ :fulfillment_tasks, [ :merchant_id, :same_day_cutoff_at ], {} ]
  ].freeze

  FOREIGN_KEYS = [
    [ :fulfillment_tasks, :merchants ],
    [ :fulfillment_task_lines, :fulfillment_tasks ],
    [ :shipping_labels, :fulfillment_tasks ],
    [ :returns, :merchants ],
    [ :returns, :fulfillment_tasks ],
    [ :bin_inventories, :warehouse_bins ]
  ].freeze

  def up
    INDEXES.each do |table, columns, options|
      add_index table, columns, **options, if_not_exists: true
    end

    FOREIGN_KEYS.each do |from, to|
      add_foreign_key from, to unless foreign_key_exists?(from, to)
    end
  end

  def down
    FOREIGN_KEYS.each do |from, to|
      remove_foreign_key from, to if foreign_key_exists?(from, to)
    end

    INDEXES.each do |table, columns, _options|
      remove_index table, column: columns, if_exists: true
    end
  end
end
