# typed: strict
# frozen_string_literal: true

class WarehouseBin < ApplicationRecord
  extend T::Sig

  MAX_CODE_LENGTH = 64
  MAX_ZONE_LENGTH = 64

  has_many :bin_inventories, dependent: :destroy

  validates :bin_code, presence: true, uniqueness: true, length: { maximum: MAX_CODE_LENGTH }
  validates :zone, presence: true, length: { maximum: MAX_ZONE_LENGTH }
end
