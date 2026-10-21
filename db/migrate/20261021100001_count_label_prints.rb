# typed: strict
# frozen_string_literal: true

class CountLabelPrints < ActiveRecord::Migration[8.1]
  def up
    add_column :shipping_labels, :print_count, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE shipping_labels
      SET print_count = COALESCE(reprint_count, 0),
          reprint_count = GREATEST(COALESCE(reprint_count, 0) - 1, 0)
    SQL
  end

  def down
    execute <<~SQL
      UPDATE shipping_labels
      SET reprint_count = print_count
    SQL

    remove_column :shipping_labels, :print_count
  end
end
