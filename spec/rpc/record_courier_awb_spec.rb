# typed: false

require "rails_helper"
require "fulfillment/v1/task_services_pb"

RSpec.describe "Rpc::FulfillmentTaskServiceHandler#record_courier_awb" do
  let(:handler) { Rpc::FulfillmentTaskServiceHandler.new }
  let(:principal) { "cccccccc-1111-4222-8333-444444444444" }
  let!(:merchant) { create(:merchant, principal_id: principal) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, status: "packed") }

  def record(awb:, task_id: task.id, who: principal)
    handler.record_courier_awb(
      Fulfillment::V1::RecordCourierAwbRequest.new(
        merchant_principal_id: who,
        fulfillment_task_id: task_id.to_s,
        order_number: task.order_number,
        awb_number: awb
      ),
      nil
    )
  end

  it "puts the fleet's number on the parcel" do
    res = record(awb: "KNX-20260921-ABCDEFGH")

    expect(res.accepted).to be true
    expect(res.already_recorded).to be false
    expect(task.reload.shipping_label.awb_number).to eq("KNX-20260921-ABCDEFGH")
  end

  it "says so rather than failing when told the same number twice" do
    record(awb: "KNX-20260921-ABCDEFGH")
    res = record(awb: "KNX-20260921-ABCDEFGH")

    expect(res.accepted).to be true
    expect(res.already_recorded).to be true
  end

  it "takes a corrected number for the same parcel" do
    record(awb: "KNX-20260921-FIRSTONE")
    res = record(awb: "KNX-20260921-SECONDON")

    expect(res.accepted).to be true
    expect(task.reload.shipping_label.awb_number).to eq("KNX-20260921-SECONDON")
  end

  it "refuses a blank number" do
    res = record(awb: "   ")

    expect(res.accepted).to be false
    expect(res.error.error_code).to eq("BLANK_AWB")
    expect(task.reload.shipping_label).to be_nil
  end

  it "refuses a principal this warehouse holds no merchant for" do
    res = record(awb: "KNX-20260921-ABCDEFGH", who: "99999999-9999-4999-8999-999999999999")

    expect(res.accepted).to be false
    expect(res.error.error_code).to eq("UNKNOWN_MERCHANT")
  end

  it "refuses a task that is not this merchant's" do
    other = create(:fulfillment_task, merchant: create(:merchant))

    res = record(awb: "KNX-20260921-ABCDEFGH", task_id: other.id)

    expect(res.accepted).to be false
    expect(res.error.error_code).to eq("UNKNOWN_TASK")
  end
end
