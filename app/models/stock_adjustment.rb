# typed: strict
# frozen_string_literal: true

class StockAdjustment < ApplicationRecord
  extend T::Sig

  DAMAGE = "DAMAGE"
  SHRINKAGE = "SHRINKAGE"
  MISCOUNT = "MISCOUNT"
  RETURN_TO_SUPPLIER = "RETURN_TO_SUPPLIER"
  EXPIRY = "EXPIRY"

  REASONS = T.let([ DAMAGE, SHRINKAGE, MISCOUNT, RETURN_TO_SUPPLIER, EXPIRY ].freeze, T::Array[String])

  belongs_to :warehouse_bin

  validates :sku, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :adjusted_by_principal_id, presence: true
  validates :merchant_principal_id, presence: true
  validates :reason, inclusion: { in: REASONS }
  validates :quantity_delta, numericality: { only_integer: true, other_than: 0 }
end
