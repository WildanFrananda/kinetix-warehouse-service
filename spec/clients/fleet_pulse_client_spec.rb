# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe FleetPulse::GrpcClient do
  let(:client) { FleetPulse::GrpcClient.new(host: "localhost:50053") }

  def dispatch
    client.dispatch_courier(
      order_id: 101,
      order_number: "ORD-999",
      pickup_address: "Warehouse Central",
      delivery_address: "Sudirman Tower",
      merchant_principal_id: "22222222-3333-4444-5555-666666666666"
    )
  end

  describe "#dispatch_courier" do
    it "handles connection error gracefully when FleetPulse server is offline" do
      result = dispatch

      expect(result[:success]).to eq(false)
      expect(result[:driver_name]).to eq("")
      expect(result[:eta_minutes]).to eq(0)
    end

    it "reports no driver principal when it could not reach the fleet" do
      result = dispatch

      expect(result).to have_key(:driver_principal_id)
      expect(result[:driver_principal_id]).to eq("")
      expect(result[:error]).to be_present
    end
  end
end
