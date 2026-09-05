# typed: false

require "rails_helper"

RSpec.describe FleetRadarChannel, type: :channel do
  let!(:merchant) { Merchant.create!(name: "Channel Merchant Test", code: "CHAN123", cutoff_hour: 16) }

  it "subscribes to the merchant fleet radar stream" do
    subscribe(merchant_id: merchant.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from("fleet_radar:merchant:#{merchant.id}")
  end

  it "rejects subscription when merchant_id is missing" do
    subscribe(merchant_id: nil)

    expect(subscription).to be_rejected
  end
end
