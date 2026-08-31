# typed: false
require "rails_helper"

RSpec.describe "FleetRadar", type: :request do
  describe "GET /fleet_radar" do
    let!(:merchant) { Merchant.create!(name: "Luxe Fashion Radar Test", code: "LUXERADAR", cutoff_hour: 16, api_key: "luxe_radar_123") }

    let!(:staff) do
      StaffUser.create!(
        merchant: merchant,
        name: "Staff Radar",
        email: "staff@radar.id",
        role: "Warehouse Manager",
        password: "secret123"
      )
    end

    let!(:order) do
      Order.create!(
        merchant: merchant,
        order_number: "ORD-RADAR-101",
        status: "in_transit",
        buyer_name: "Radar Buyer",
        buyer_phone: "0812-9999-8888",
        shipping_address: "Sudirman Central Business District",
        total_amount: 850000.0,
        same_day_cutoff_at: Time.current + 2.hours
      )
    end

    before do
      post login_path, params: { email: "staff@radar.id", password: "secret123" }
    end

    it "renders the interactive dark mode fleet radar map successfully" do
      get fleet_radar_path(merchant_id: merchant.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("FleetPulse Live Courier Telemetry")
      expect(response.body).to include("fleet-map")
      expect(response.body).to include("ORD-RADAR-101")
      expect(response.body).to include("Sudirman Central Business District")
    end

  end
end
