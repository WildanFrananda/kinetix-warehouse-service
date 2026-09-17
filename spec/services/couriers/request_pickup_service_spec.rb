# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Couriers::RequestPickupService, type: :service do
  let(:owner) { "bbbbbbbb-1111-2222-3333-444444444444" }
  let(:driver) { "cccccccc-1111-2222-3333-444444444444" }
  let(:merchant) { create(:merchant, principal_id: owner) }
  let(:order) do
    create(:order, merchant: merchant, order_number: "ORD-PICKUP-1",
                   shipping_address: "Jl. Sudirman 5, Jakarta")
  end

  let(:fleet_client) { FleetPulse::GrpcClient.new(host: "localhost:1") }
  let(:service) { described_class.new(fleet_client: fleet_client) }

  around do |example|
    previous = ENV["WAREHOUSE_PICKUP_ADDRESS"]
    ENV["WAREHOUSE_PICKUP_ADDRESS"] = "Gudang Kinetix, Jakarta"
    example.run
    ENV["WAREHOUSE_PICKUP_ADDRESS"] = previous
  end

  def dispatched(overrides = {})
    {
      success: true,
      dispatch_ref: "DISP-42",
      driver_principal_id: driver,
      driver_name: "Budi",
      eta_minutes: 10
    }.merge(overrides)
  end

  it "names the order by its order number, which is what every service shares" do
    expect(fleet_client).to receive(:dispatch_courier).with(
      hash_including(order_number: "ORD-PICKUP-1", merchant_principal_id: owner,
                     pickup_address: "Gudang Kinetix, Jakarta",
                     delivery_address: "Jl. Sudirman 5, Jakarta")
    ).and_return(dispatched)

    expect(service.call(order: order)).to be_success
  end

  it "carries back the driver principal, which decides who is paid" do
    allow(fleet_client).to receive(:dispatch_courier).and_return(dispatched)

    result = service.call(order: order)

    expect(result.data.driver_principal_id).to eq(driver)
    expect(result.data.dispatch_ref).to eq("DISP-42")
  end

  it "refuses a dispatch that reports success but names no driver" do
    allow(fleet_client).to receive(:dispatch_courier).and_return(dispatched(driver_principal_id: ""))

    result = service.call(order: order)

    expect(result).not_to be_success
    expect(result.error).to match(/named no driver/)
  end

  it "reports the fleet's own refusal rather than inventing one" do
    allow(fleet_client).to receive(:dispatch_courier)
      .and_return({ success: false, error: "NO_DRIVER_AVAILABLE", driver_principal_id: "" })

    result = service.call(order: order)

    expect(result).not_to be_success
    expect(result.error).to eq("NO_DRIVER_AVAILABLE")
  end

  it "refuses an order with no shipping address rather than dispatching to nowhere" do
    order.update!(shipping_address: nil)
    expect(fleet_client).not_to receive(:dispatch_courier)

    expect(service.call(order: order)).not_to be_success
  end

  it "refuses when the merchant has no principal, so the fleet is never told the wrong owner" do
    merchant.update!(principal_id: nil)
    expect(fleet_client).not_to receive(:dispatch_courier)

    expect(service.call(order: order)).not_to be_success
  end
end
