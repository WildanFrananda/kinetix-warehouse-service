# typed: strict
# frozen_string_literal: true

class StockReservation < ApplicationRecord
  extend T::Sig

  belongs_to :merchant
  belongs_to :bin_inventory, optional: true

  validates :order_number, presence: true,
                           length: { maximum: StockOperation::MAX_ORDER_NUMBER_LENGTH }
  validates :sku, presence: true, length: { maximum: StockOperation::MAX_SKU_LENGTH }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than: 0 }, if: :held?

  scope :held, -> { where(released_at: nil) }
  scope :held_before, ->(cutoff) { held.where(created_at: ...cutoff) }

  sig { returns(T::Boolean) }
  def held?
    released_at.nil?
  end
end
