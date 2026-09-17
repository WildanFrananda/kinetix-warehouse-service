# typed: strict
# frozen_string_literal: true

class StockReceipt < ApplicationRecord
  extend T::Sig

  belongs_to :warehouse_bin

  validates :sku, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :received_by_principal_id, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
