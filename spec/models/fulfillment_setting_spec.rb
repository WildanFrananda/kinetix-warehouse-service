# typed: false

require "rails_helper"

RSpec.describe FulfillmentSetting do
  it "can be destroyed, so the seeds can clear the table" do
    setting = create(:fulfillment_setting)
    create(:fulfillment_task, fulfillment_setting: setting)

    expect { setting.destroy! }.not_to raise_error
    expect(FulfillmentSetting.exists?(setting.id)).to be(false)
  end

  describe "the packing cutoff" do
    it "is the schema's default for a merchant projected before it set one" do
      expect(FulfillmentSetting.create!(merchant_principal_id: SecureRandom.uuid).cutoff_hour).to eq(12)
    end

    it "is never absent" do
      setting = FulfillmentSetting.create!(merchant_principal_id: SecureRandom.uuid)

      expect { setting.update_column(:cutoff_hour, nil) }.to raise_error(ActiveRecord::NotNullViolation)
    end

    it "is an hour of the day" do
      setting = FulfillmentSetting.create!(merchant_principal_id: SecureRandom.uuid)

      expect { setting.update_column(:cutoff_hour, 24) }.to raise_error(ActiveRecord::StatementInvalid, /cutoff_hour_is_an_hour/)
    end
  end
end
