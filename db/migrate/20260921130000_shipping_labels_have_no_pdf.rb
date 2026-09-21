# typed: strict
# frozen_string_literal: true

class ShippingLabelsHaveNoPdf < ActiveRecord::Migration[8.0]
  def change
    remove_column :shipping_labels, :pdf_url, :string
  end
end
