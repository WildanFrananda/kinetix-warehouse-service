# typed: strict
# frozen_string_literal: true

class EveryMerchantHasACutoffHour < ActiveRecord::Migration[8.1]
  UNTIL_SET = 12

  def up
    change_column_default :merchants, :cutoff_hour, from: nil, to: UNTIL_SET
    change_column_null :merchants, :cutoff_hour, false, UNTIL_SET
    add_check_constraint :merchants,
                         "cutoff_hour BETWEEN 0 AND 23",
                         name: "merchants_cutoff_hour_is_an_hour",
                         if_not_exists: true
  end

  def down
    remove_check_constraint :merchants, name: "merchants_cutoff_hour_is_an_hour", if_exists: true
    change_column_null :merchants, :cutoff_hour, true
    change_column_default :merchants, :cutoff_hour, from: UNTIL_SET, to: nil
  end
end
