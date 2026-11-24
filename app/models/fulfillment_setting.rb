# typed: strict

class FulfillmentSetting < ApplicationRecord
  extend T::Sig
  has_many :fulfillment_tasks,
           primary_key: :merchant_principal_id,
           foreign_key: :merchant_principal_id,
           dependent: :destroy

  validates :merchant_principal_id, presence: true, uniqueness: true
end
