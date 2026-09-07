# typed: strict
# frozen_string_literal: true

class StockReservation < ApplicationRecord
  extend T::Sig

  belongs_to :merchant

  validates :order_number, presence: true
  validates :sku, presence: true
  validates :quantity, numericality: { greater_than: 0 }

  scope :held, -> { where(released_at: nil) }

  sig { returns(T::Boolean) }
  def held?
    released_at.nil?
  end
end
