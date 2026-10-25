# typed: strict
# frozen_string_literal: true

class StockReceipt < ApplicationRecord
  extend T::Sig

  MAX_NOTE_LENGTH = 1000

  belongs_to :warehouse_bin

  validates :sku, presence: true
  validates :idempotency_key, presence: true, uniqueness: { scope: :merchant_principal_id }
  validates :received_by_principal_id, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :note, length: { maximum: MAX_NOTE_LENGTH }
end
