# typed: false

require "rails_helper"

RSpec.describe Couriers::DispatchFleetPulseService, type: :service do
  let!(:merchant) { create(:merchant) }
  let!(:order) { create(:order, merchant: merchant, order_number: "ORD-FP-1", status: "packed") }
  let(:service) { described_class.new }

  let(:unreachable) { "http://127.0.0.1:1/api/v1/merchant/orders" }

  describe "when FleetPulse cannot be reached" do
    it "fails rather than reporting a dispatch that never happened" do
      result = service.call(merchant_id: merchant.id, order_id: order.id, fleet_pulse_url: unreachable)

      expect(result).to be_failure
      expect(result.data).to be_nil
    end

    it "tells the operator the order was not dispatched, without naming the exception" do
      result = service.call(merchant_id: merchant.id, order_id: order.id, fleet_pulse_url: unreachable)

      expect(result.error).to include("was not dispatched")
      expect(result.error).to include("status is unchanged")
      expect(result.error).not_to include("Errno")
      expect(result.error).not_to include("Connection refused")
    end

    it "writes the exception and the correlation id to the log" do
      allow(Rails.logger).to receive(:error)

      Kinetix::RequestId.with("kinetix-trace-under-test") do
        service.call(merchant_id: merchant.id, order_id: order.id, fleet_pulse_url: unreachable)
      end

      expect(Rails.logger).to have_received(:error).with(
        a_string_including("Errno::ECONNREFUSED")
          .and(a_string_including("request_id=kinetix-trace-under-test"))
      )
    end

    it "leaves the order's status alone" do
      expect {
        service.call(merchant_id: merchant.id, order_id: order.id, fleet_pulse_url: unreachable)
      }.not_to change { order.reload.status }
    end
  end

  describe "when the order does not exist" do
    it "fails before any call is attempted" do
      result = service.call(merchant_id: merchant.id, order_id: 0, fleet_pulse_url: unreachable)

      expect(result).to be_failure
      expect(result.error).to eq("Order not found")
    end
  end
end
