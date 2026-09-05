# spec/models/staff_user_spec.rb
require "rails_helper"

RSpec.describe StaffUser, type: :model do
  let(:merchant) { Merchant.create!(code: "TST-01", name: "Test Merchant", cutoff_hour: 14) }


  describe "BCrypt Password Authentication" do
    it "hashes password and authenticates valid staff user credentials" do
      staff = StaffUser.create!(
        merchant: merchant,
        name: "Test Staff",
        email: "staff@test.com",
        role: "Warehouse Manager",
        password: "secret_password"
      )

      expect(staff.password_digest).not_to be_nil
      expect(staff.authenticate("secret_password")).to eq(staff)
      expect(staff.authenticate("wrong_password")).to be_falsey
    end
  end
end
