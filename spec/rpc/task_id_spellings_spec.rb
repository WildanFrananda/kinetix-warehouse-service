# typed: false
# frozen_string_literal: true

require "rails_helper"
require "fulfillment/v1/task_services_pb"

RSpec.describe "task ids order sends over gRPC" do
  let(:handler) { Rpc::FulfillmentTaskServiceHandler.new }
  let(:principal) { "cccccccc-1111-4222-8333-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, status: "packed") }

  def misspellings(id)
    [ "0x#{id.to_s(16)}", "0#{id.to_s(8)}", "0o#{id.to_s(8)}", "0b#{id.to_s(2)}", " #{id} ", "+#{id}" ]
  end

  it "records a tracking number only for an id written in decimal digits" do
    misspellings(task.id).each do |spelling|
      res = handler.record_courier_awb(
        Fulfillment::V1::RecordCourierAwbRequest.new(
          merchant_principal_id: principal,
          fulfillment_task_id: spelling,
          order_number: task.order_number,
          awb_number: "KNX-20261023-SPELLING"
        ),
        nil
      )

      expect(res.accepted).to be(false), "#{spelling.inspect} was accepted"
      expect(res.error.error_code).to eq("UNKNOWN_TASK")
    end

    expect(task.reload.shipping_label).to be_nil
  end

  it "cancels only a task whose id is written in decimal digits" do
    misspellings(task.id).each do |spelling|
      res = handler.cancel_fulfillment_task(
        Fulfillment::V1::CancelFulfillmentTaskRequest.new(merchant_principal_id: principal, task_id: spelling),
        nil
      )

      expect(res.success).to be(false), "#{spelling.inspect} cancelled the task"
    end

    expect(task.reload.status).to eq("packed")
  end

  it "still cancels the task named in digits" do
    res = handler.cancel_fulfillment_task(
      Fulfillment::V1::CancelFulfillmentTaskRequest.new(merchant_principal_id: principal, task_id: task.id.to_s),
      nil
    )

    expect(res.success).to be(true)
    expect(task.reload.status).to eq("cancelled")
  end
end
