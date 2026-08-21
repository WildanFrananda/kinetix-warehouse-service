# typed: strict
# frozen_string_literal: true

class BinInventory < ApplicationRecord
  extend T::Sig

  belongs_to :warehouse_bin

  validates :sku, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :reserved_quantity, numericality: { greater_than_or_equal_to: 0 }

  sig { returns(Integer) }
  def available_quantity
    [quantity - reserved_quantity, 0].max
  end
end
