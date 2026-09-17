# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::UpdateOrderStatusService, type: :service do
  let(:driver) { "cccccccc-1111-2222-3333-444444444444" }
  let(:merchant) { create(:merchant, principal_id: "bbbbbbbb-1111-2222-3333-444444444444") }
  let!(:order) do
    create(:order, merchant: merchant, order_number: "ORD-PACK-1", status: "picking",
                   shipping_address: "Jl. Sudirman 5, Jakarta")
  end

  let(:pickup) do
    Couriers::RequestPickupService.new(fleet_client: FleetPulse::GrpcClient.new(host: "localhost:1"))
  end
  let(:service) { described_class.new(request_pickup_service: pickup) }

  def dispatched
    BaseService::Result.new(
      success: true,
      data: Couriers::RequestPickupService::ResultData.new(
        order_number: "ORD-PACK-1", dispatch_ref: "DISP-9",
        driver_principal_id: driver, driver_name: "Budi", eta_minutes: 10
      ),
      error: nil
    )
  end

  def refused(message)
    BaseService::Result.new(success: false, data: nil, error: message)
  end

  def pack!
    service.call(merchant_id: merchant.id, order_id: order.id, new_status: "packed")
  end

  it "asks the fleet for a courier when an order becomes packed" do
    expect(pickup).to receive(:call).with(order: an_instance_of(Order)).and_return(dispatched)

    result = pack!

    expect(result).to be_success
    expect(result.data.courier_requested).to be(true)
    expect(result.data.driver_principal_id).to eq(driver)
  end

  it "does not ask for a courier on a status that is not packed" do
    expect(pickup).not_to receive(:call)

    result = service.call(merchant_id: merchant.id, order_id: order.id, new_status: "picking")

    expect(result).to be_success
    expect(result.data.courier_requested).to be(false)
  end

  it "still records the packing when no courier could be dispatched" do
    allow(pickup).to receive(:call).and_return(refused("NO_DRIVER_AVAILABLE"))

    result = pack!

    expect(result).to be_success
    expect(order.reload.status).to eq("packed")
    expect(result.data.courier_requested).to be(false)
    expect(result.data.courier_error).to eq("NO_DRIVER_AVAILABLE")
  end

  it "survives the fleet raising, and says so" do
    allow(pickup).to receive(:call).and_raise(GRPC::Unavailable.new("no connection"))

    result = pack!

    expect(result).to be_success
    expect(order.reload.status).to eq("packed")
    expect(result.data.courier_requested).to be(false)
    expect(result.data.courier_error).to match(/no courier is coming/)
  end
end
