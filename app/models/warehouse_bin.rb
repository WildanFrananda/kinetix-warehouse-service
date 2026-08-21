# typed: strict
# frozen_string_literal: true

class WarehouseBin < ApplicationRecord
  extend T::Sig

  has_many :bin_inventories, dependent: :destroy

  validates :bin_code, presence: true, uniqueness: true
  validates :zone, presence: true
end
