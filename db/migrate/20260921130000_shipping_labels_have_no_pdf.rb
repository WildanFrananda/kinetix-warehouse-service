# typed: strict
# frozen_string_literal: true

class ShippingLabelsHaveNoPdf < ActiveRecord::Migration[8.0]
  def up
    remove_column :shipping_labels, :pdf_url, if_exists: true
  end

  def down
    add_column :shipping_labels, :pdf_url, :string
  end
end
