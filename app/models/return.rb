# typed: strict

class Return < ApplicationRecord
  extend T::Sig

  belongs_to :merchant
  belongs_to :fulfillment_task

  validates :reason, presence: true
  validates :status, presence: true
end
