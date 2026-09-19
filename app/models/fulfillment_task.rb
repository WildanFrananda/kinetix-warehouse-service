# typed: strict

class FulfillmentTask < ApplicationRecord
  extend T::Sig

  STATUSES = T.let(%w[received picking packed cancelled].freeze, T::Array[String])

  belongs_to :merchant
  has_many :fulfillment_task_lines, dependent: :destroy
  has_one :shipping_label, dependent: :destroy
  has_one :return_request, class_name: "Return", dependent: :destroy

  validates :order_number, presence: true, uniqueness: { scope: :merchant_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :same_day_cutoff_at, presence: true
end
