# typed: strict
# frozen_string_literal: true

class ReturnsBelongToOrder < ActiveRecord::Migration[8.0]
  def up
    drop_table :returns, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the returns this table held were migrated to order; recreating it empty would not " \
          "bring them back, and a second home for them is what W10 removed"
  end
end
