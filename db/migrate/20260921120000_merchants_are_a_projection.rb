# typed: strict
# frozen_string_literal: true

class MerchantsAreAProjection < ActiveRecord::Migration[8.0]
  def up
    remove_column :merchants, :code, if_exists: true
    remove_column :merchants, :name, if_exists: true
  end

  def down
    add_column :merchants, :name, :string
    add_column :merchants, :code, :string
  end
end
