# typed: strict
# frozen_string_literal: true

class BinCodesZonesAndNotesHaveLimits < ActiveRecord::Migration[8.1]
  LIMITS = [
    [ :warehouse_bins, :bin_code, 64 ],
    [ :warehouse_bins, :zone, 64 ],
    [ :stock_receipts, :note, 1000 ],
    [ :stock_adjustments, :note, 1000 ]
  ].freeze

  SHOWN_ROWS = 20

  def up
    over = LIMITS.filter_map { |table, column, limit| over_limit(table, column, limit) }
    raise refusal(over) if over.any?

    LIMITS.each do |table, column, limit|
      change_column table, column, :string, limit: limit
    end
  end

  def down
    LIMITS.each do |table, column, _limit|
      change_column table, column, :string, limit: nil
    end
  end

  private

  def over_limit(table, column, limit)
    rows = select_all(<<~SQL).to_a
      SELECT id, char_length(#{column}) AS length
      FROM #{table}
      WHERE char_length(#{column}) > #{limit}
      ORDER BY id
    SQL
    return nil if rows.empty?

    shown = rows.first(SHOWN_ROWS).map { |row| "id #{row['id']} (#{row['length']})" }
    more = rows.size > SHOWN_ROWS ? " and #{rows.size - SHOWN_ROWS} more" : ""

    "#{table}.#{column} over #{limit} characters: #{shown.join(', ')}#{more}"
  end

  def refusal(over)
    "these rows are longer than the column may hold, and shortening them would change what staff wrote. " \
      "Shorten each value by hand, then migrate again: #{over.join('; ')}"
  end
end
