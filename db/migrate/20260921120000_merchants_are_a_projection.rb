# typed: strict
# frozen_string_literal: true

class MerchantsAreAProjection < ActiveRecord::Migration[8.0]
  def change
    remove_index :merchants, :code, unique: true
    remove_column :merchants, :code, :string
    remove_column :merchants, :name, :string
  end
end
