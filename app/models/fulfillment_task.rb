# typed: strict

class FulfillmentTask < ApplicationRecord
  extend T::Sig

  STATUSES = T.let(%w[received packing packed cancelled].freeze, T::Array[String])

  belongs_to :fulfillment_setting,
             primary_key: :merchant_principal_id,
             foreign_key: :merchant_principal_id
  has_many :fulfillment_task_lines, dependent: :destroy
  has_one :shipping_label, dependent: :destroy
  validates :order_number, presence: true, uniqueness: { scope: :merchant_principal_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :same_day_cutoff_at, presence: true
end
