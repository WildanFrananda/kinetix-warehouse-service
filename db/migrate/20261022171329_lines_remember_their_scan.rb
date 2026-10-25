# typed: strict
# frozen_string_literal: true

class LinesRememberTheirScan < ActiveRecord::Migration[8.1]
  def change
    add_column :fulfillment_task_lines, :scanned_at, :datetime
  end
end
