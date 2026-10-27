# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "how long a string another service sends over gRPC may be" do
  include_context "warehouse serves gRPC over mTLS"

  let(:principal) { "cccccccc-1111-4222-8333-888888888888" }
  let!(:merchant) { create(:merchant, principal_id: principal) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, order_number: "ORD-LONG-1", status: "packed") }

  def line(sku)
    Fulfillment::V1::FulfillmentTaskLine.new(sku: sku, quantity: 1)
  end

  def create_task(order_number: "ORD-LONG-2", sku: "S")
    tasks.create_fulfillment_task(
      Fulfillment::V1::CreateFulfillmentTaskRequest.new(
        merchant_principal_id: principal,
        order_number: order_number,
        lines: [ line(sku) ]
      )
    )
  end

  def too_long(field, limit)
    raise_error(GRPC::InvalidArgument) do |error|
      expect(error.details).to eq("#{field} must be at most #{limit} characters")
    end
  end

  describe "CreateFulfillmentTask" do
    it "refuses an order number over 64 characters, and creates no task" do
      expect { create_task(order_number: "O" * 65) }.to too_long("order_number", 64)
      expect(FulfillmentTask.count).to eq(1)
    end

    it "takes an order number of 64 characters" do
      expect(create_task(order_number: "O" * 64).success).to be(true)
    end

    it "refuses a line's SKU over 128 characters, and creates no task" do
      expect { create_task(sku: "S" * 129) }.to too_long("lines.sku", 128)
      expect(FulfillmentTask.count).to eq(1)
    end

    it "takes a SKU of 128 characters" do
      expect(create_task(sku: "S" * 128).success).to be(true)
    end
  end

  describe "RecordCourierAwb" do
    def record(awb)
      tasks.record_courier_awb(
        Fulfillment::V1::RecordCourierAwbRequest.new(
          merchant_principal_id: principal,
          fulfillment_task_id: task.id.to_s,
          awb_number: awb
        )
      )
    end

    it "refuses a tracking number over 64 characters, and writes no label" do
      expect { record("K" * 65) }.to too_long("awb_number", 64)
      expect(task.reload.shipping_label).to be_nil
    end

    it "takes a tracking number of 64 characters" do
      expect(record("K" * 64).accepted).to be(true)
    end
  end

  describe "CheckBinStock and CheckBinStockBatch" do
    it "refuses a SKU over 128 characters" do
      request = Fulfillment::V1::CheckBinStockRequest.new(merchant_principal_id: principal, sku: "S" * 129)

      expect { stock("catalog").check_bin_stock(request) }.to too_long("sku", 128)
    end

    it "refuses a batch holding a SKU over 128 characters" do
      request = Fulfillment::V1::CheckBinStockBatchRequest.new(
        merchant_principal_id: principal,
        skus: [ "S", "S" * 129 ]
      )

      expect { stock("catalog").check_bin_stock_batch(request) }.to too_long("skus", 128)
    end

    it "answers a SKU of 128 characters" do
      request = Fulfillment::V1::CheckBinStockRequest.new(merchant_principal_id: principal, sku: "S" * 128)

      expect(stock("catalog").check_bin_stock(request).found).to be(false)
    end
  end
end
