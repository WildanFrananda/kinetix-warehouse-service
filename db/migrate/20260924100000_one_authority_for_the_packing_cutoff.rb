# typed: strict
# frozen_string_literal: true

class OneAuthorityForThePackingCutoff < ActiveRecord::Migration[8.0]
  def up
    change_column_default :merchants, :cutoff_hour, from: 14, to: nil
  end

  def down
    change_column_default :merchants, :cutoff_hour, from: nil, to: 14
  end
end
