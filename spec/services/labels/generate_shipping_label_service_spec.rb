# typed: false

require 'rails_helper'

RSpec.describe Labels::GenerateShippingLabelService, type: :service do
  let!(:merchant) { create(:merchant) }
  let!(:task) { create(:fulfillment_task, merchant: merchant) }
  let(:service) { described_class.new }

  it "refuses to print a label for a parcel no courier has been assigned to" do
    result = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)

    expect(result.success?).to be false
    expect(result.error).to include("no tracking number")
    expect(task.reload.shipping_label).to be_nil
  end

  it "counts reprints once the courier's number is recorded" do
    task.create_shipping_label!(awb_number: "KNX-20260921-ABCDEFGH", reprint_count: 0)

    result1 = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)
    expect(result1.success?).to be true
    expect(result1.data.reprint_count).to eq(1)

    result2 = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)
    expect(result2.success?).to be true
    expect(result2.data.reprint_count).to eq(2)
  end

  it "does not name a document it has not produced" do
    task.create_shipping_label!(awb_number: "KNX-20260921-ABCDEFGH", reprint_count: 0)

    result = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)

    expect(result.data).not_to respond_to(:pdf_url)
    expect(ShippingLabel.column_names).not_to include("pdf_url")
  end

  it "carries the number the fleet issued, which is what the packer scans" do
    task.create_shipping_label!(awb_number: "KNX-20260921-ABCDEFGH", reprint_count: 0)

    result = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)

    expect(result.data.awb_number).to eq("KNX-20260921-ABCDEFGH")
    expect(task.reload.shipping_label.awb_number).to eq("KNX-20260921-ABCDEFGH")
  end

  it "mints nothing of its own" do
    service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)

    expect(ShippingLabel.where.not(awb_number: nil).where("awb_number LIKE ?", "AWB-%")).to be_empty
  end
end
