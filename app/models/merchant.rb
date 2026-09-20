# typed: strict

class Merchant < ApplicationRecord
  extend T::Sig
  has_many :fulfillment_tasks, dependent: :destroy
  has_many :returns, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
