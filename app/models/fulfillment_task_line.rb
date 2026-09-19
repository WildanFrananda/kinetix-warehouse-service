# typed: strict

class FulfillmentTaskLine < ApplicationRecord
  extend T::Sig

  belongs_to :fulfillment_task

  validates :sku, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
end
