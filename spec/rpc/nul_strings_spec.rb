# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "a NUL in a string another service sends over gRPC" do
  include_context "warehouse serves gRPC over mTLS"

  let(:principal) { "cccccccc-1111-4222-8333-666666666666" }
  let!(:merchant) { create(:merchant, principal_id: principal) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, order_number: "ORD-NUL-1", status: "packed") }

  def create_request(**fields)
    Fulfillment::V1::CreateFulfillmentTaskRequest.new(
      merchant_principal_id: principal,
      order_number: "ORD-2",
      lines: [ line("S") ],
      **fields
    )
  end

  def line(sku)
    Fulfillment::V1::FulfillmentTaskLine.new(sku: sku, quantity: 1)
  end

  def key(value)
    Common::V1::IdempotencyKey.new(key: value)
  end

  def refused(field)
    raise_error(GRPC::InvalidArgument) do |error|
      expect(error.details).to eq("#{field} must not contain a NUL character")
    end
  end

  it "still answers the same call without one" do
    request = Fulfillment::V1::CheckBinStockRequest.new(merchant_principal_id: principal, sku: "S")

    res = stock("catalog").check_bin_stock(request)

    expect(res.found).to be(false)
  end

  {
    "order_number" => -> { create_request(order_number: "ORD\u00002") },
    "merchant_principal_id" => -> { create_request(merchant_principal_id: "#{principal}\u0000") },
    "lines.sku" => -> { create_request(lines: [ line("S"), line("S\u0000") ]) },
    "idempotency_key.key" => -> { create_request(idempotency_key: key("K\u0000")) }
  }.each do |field, build|
    it "is refused in CreateFulfillmentTask's #{field} as INVALID_ARGUMENT, and no task is created" do
      request = instance_exec(&build)

      expect { tasks.create_fulfillment_task(request) }.to refused(field)
      expect(FulfillmentTask.count).to eq(1)
    end
  end

  it "is refused in CancelFulfillmentTask's task_id, and the task is left as it is" do
    request = Fulfillment::V1::CancelFulfillmentTaskRequest.new(
      merchant_principal_id: principal,
      task_id: "#{task.id}\u0000"
    )

    expect { tasks.cancel_fulfillment_task(request) }.to refused("task_id")
    expect(task.reload.status).to eq("packed")
  end

  it "is refused in RecordCourierAwb's awb_number, and no label is written" do
    request = Fulfillment::V1::RecordCourierAwbRequest.new(
      merchant_principal_id: principal,
      fulfillment_task_id: task.id.to_s,
      order_number: task.order_number,
      awb_number: "KNX-20261027-\u0000"
    )

    expect { tasks.record_courier_awb(request) }.to refused("awb_number")
    expect(task.reload.shipping_label).to be_nil
  end

  it "is refused in CheckBinStock's sku" do
    request = Fulfillment::V1::CheckBinStockRequest.new(merchant_principal_id: principal, sku: "S\u0000")

    expect { stock("catalog").check_bin_stock(request) }.to refused("sku")
  end

  it "is refused in any one of CheckBinStockBatch's skus" do
    request = Fulfillment::V1::CheckBinStockBatchRequest.new(
      merchant_principal_id: principal,
      skus: [ "A", "B\u0000" ]
    )

    expect { stock("catalog").check_bin_stock_batch(request) }.to refused("skus")
  end

  it "is refused in ReserveStock's order_number, and nothing is reserved or written to the ledger" do
    request = Fulfillment::V1::ReserveStockRequest.new(
      merchant_principal_id: principal, sku: "S", quantity: 1, order_number: "ORD\u00003"
    )

    expect { stock.reserve_stock(request) }.to refused("order_number")
    expect(StockOperation.count).to eq(0)
    expect(StockReservation.count).to eq(0)
  end

  it "is refused in ReleaseStock's sku" do
    request = Fulfillment::V1::ReleaseStockRequest.new(
      merchant_principal_id: principal, sku: "S\u0000", quantity: 1, order_number: "ORD-3"
    )

    expect { stock.release_stock(request) }.to refused("sku")
    expect(StockOperation.count).to eq(0)
  end

  it "is answered only after the caller's identity, so a peer off the allow list is still PERMISSION_DENIED" do
    request = Fulfillment::V1::CheckBinStockRequest.new(merchant_principal_id: principal, sku: "S\u0000")

    expect { stock("matching").check_bin_stock(request) }.to raise_error(GRPC::PermissionDenied)
  end
end
