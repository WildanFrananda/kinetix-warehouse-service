# typed: strict

require "bcrypt"

class StaffUser < ApplicationRecord
  extend T::Sig

  has_secure_password validations: false

  belongs_to :merchant

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
  validates :role, presence: true
end
