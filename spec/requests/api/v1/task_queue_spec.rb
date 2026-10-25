# typed: false

require "rails_helper"
require "fulfillment/v1/fulfillment_services_pb"
require "fulfillment/v1/task_services_pb"

RSpec.describe "Api::V1::FulfillmentTasks#queue", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-4333-8444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id, cutoff_hour: 14) }
  let(:headers) { bearer(access_token(principal_id: principal_id)) }

  def queue
    get "/api/v1/fulfillment_tasks/queue", headers: headers
    response.parsed_body
  end

  def task(status, order_number, cutoff: 1.hour.ago)
    create(:fulfillment_task, merchant: merchant, status: status, order_number: order_number,
                              same_day_cutoff_at: cutoff)
  end

  describe "what is on it" do
    before do
      task("received", "ORD-RECEIVED")
      task("packing", "ORD-PACKING")
      task("packed", "ORD-PACKED-WAITING")
      task("cancelled", "ORD-CANCELLED")

      printed = task("packed", "ORD-PACKED-PRINTED")
      printed.create_shipping_label!(awb_number: "KNX-1", reprint_count: 0)
      post "/api/v1/fulfillment_tasks/#{printed.id}/label", headers: headers
    end

    it "holds the work left: tasks to pack, and packed parcels whose label is not printed yet" do
      expect(queue.map { |card| card["order_number"] })
        .to contain_exactly("ORD-RECEIVED", "ORD-PACKING", "ORD-PACKED-WAITING")
    end

    it "calls only an unpacked task overdue" do
      urgency = queue.to_h { |card| [ card["order_number"], card["sla_urgency"] ] }

      expect(urgency["ORD-RECEIVED"]).to eq("overdue")
      expect(urgency["ORD-PACKING"]).to eq("overdue")
      expect(urgency["ORD-PACKED-WAITING"]).to eq("packed")
    end
  end

  describe "where to pick each line from" do
    let!(:bin) { WarehouseBin.create!(bin_code: "Z-09-3", zone: "Z", shelf_level: 3) }

    before do
      BinInventory.create!(
        warehouse_bin: bin, sku: "GAMIS-RED-M", quantity: 10, reserved_quantity: 0,
        merchant_principal_id: principal_id
      )
    end

    it "names the bin the order's stock was reserved from" do
      reserved = Rpc::BinStockServiceHandler.new.reserve_stock(
        Fulfillment::V1::ReserveStockRequest.new(
          merchant_principal_id: principal_id,
          sku: "GAMIS-RED-M",
          quantity: 2,
          order_number: "ORD-PICK"
        ),
        nil
      )
      expect(reserved.success).to be(true)

      created = Rpc::FulfillmentTaskServiceHandler.new.create_fulfillment_task(
        Fulfillment::V1::CreateFulfillmentTaskRequest.new(
          merchant_principal_id: principal_id,
          order_number: "ORD-PICK",
          lines: [ Fulfillment::V1::FulfillmentTaskLine.new(sku: "GAMIS-RED-M", quantity: 2) ]
        ),
        nil
      )
      expect(created.success).to be(true)

      card = queue.find { |item| item["order_number"] == "ORD-PICK" }

      expect(card["lines"]).to eq(
        [ { "sku" => "GAMIS-RED-M", "quantity" => 2, "bin_location" => "Z-09-3", "scanned" => false } ]
      )
    end
  end
end
