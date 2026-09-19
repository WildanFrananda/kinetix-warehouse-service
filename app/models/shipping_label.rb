# typed: strict

class ShippingLabel < ApplicationRecord
  extend T::Sig

  belongs_to :fulfillment_task

  validates :awb_number, presence: true, uniqueness: true
  validates :reprint_count, numericality: { greater_than_or_equal_to: 0 }
end
