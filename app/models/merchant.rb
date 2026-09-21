# typed: strict

class Merchant < ApplicationRecord
  extend T::Sig
  has_many :fulfillment_tasks, dependent: :destroy
  has_many :returns, dependent: :destroy

  validates :principal_id, presence: true, uniqueness: true
end
