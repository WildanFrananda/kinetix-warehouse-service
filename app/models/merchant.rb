# typed: strict

class Merchant < ApplicationRecord
  extend T::Sig

  has_many :staff_users, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :returns, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :latitude, presence: true
  validates :longitude, presence: true

  sig { returns(Float) }
  def latitude_float
    (T.unsafe(self).latitude || BigDecimal("-6.2088")).to_f
  end

  sig { returns(Float) }
  def longitude_float
    (T.unsafe(self).longitude || BigDecimal("106.8456")).to_f
  end
end
