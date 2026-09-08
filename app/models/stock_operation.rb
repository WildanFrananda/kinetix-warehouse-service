# typed: strict
# frozen_string_literal: true

class StockOperation < ApplicationRecord
  extend T::Sig

  RESERVE = "reserve"
  RELEASE = "release"
  MAX_KEY_LENGTH = 255
  MAX_ORDER_NUMBER_LENGTH = 64
  MAX_SKU_LENGTH = 128

  belongs_to :merchant

  validates :operation, inclusion: { in: [ RESERVE, RELEASE ] }
  validates :idempotency_key, presence: true, length: { maximum: MAX_KEY_LENGTH }
  validates :request_digest, presence: true
  validates :order_number, presence: true, length: { maximum: MAX_ORDER_NUMBER_LENGTH }
  validates :sku, presence: true, length: { maximum: MAX_SKU_LENGTH }

  scope :older_than, ->(cutoff) { where(created_at: ...cutoff) }

  sig { params(fields: T::Array[String]).returns(String) }
  def self.digest_of(fields)
    Digest::SHA256.hexdigest(fields.join("\0"))
  end
end
