# typed: false

require "rails_helper"

RSpec.describe Merchant do
  it "can be destroyed, so the seeds can clear the table" do
    merchant = create(:merchant)
    create(:fulfillment_task, merchant: merchant)

    expect { merchant.destroy! }.not_to raise_error
    expect(Merchant.exists?(merchant.id)).to be(false)
  end

  describe "the packing cutoff" do
    it "is the schema's default for a merchant projected before it set one" do
      expect(Merchant.create!(principal_id: SecureRandom.uuid).cutoff_hour).to eq(12)
    end

    it "is never absent" do
      merchant = Merchant.create!(principal_id: SecureRandom.uuid)

      expect { merchant.update_column(:cutoff_hour, nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "is an hour of the day" do
      merchant = Merchant.create!(principal_id: SecureRandom.uuid)

      expect { merchant.update_column(:cutoff_hour, 24) }.to raise_error(ActiveRecord::StatementInvalid, /cutoff_hour_is_an_hour/)
    end
  end
end
