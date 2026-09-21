# typed: false

require 'rails_helper'

RSpec.describe Labels::GenerateShippingLabelService, type: :service do
  let!(:merchant) { create(:merchant) }
  let!(:task) { create(:fulfillment_task, merchant: merchant) }
  let(:service) { described_class.new }

  it "generates AWB shipping label on first call and increments reprint_count on second call" do
    result1 = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)
    expect(result1.success?).to be true
    expect(result1.data.reprint_count).to eq(1)

    result2 = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)
    expect(result2.success?).to be true
    expect(result2.data.reprint_count).to eq(2)
  end

  it "does not name a document it has not produced" do
    result = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)

    expect(result.data).not_to respond_to(:pdf_url)
    expect(ShippingLabel.column_names).not_to include("pdf_url")
  end

  it "still carries the number the packer scans" do
    result = service.call(merchant_id: merchant.id, fulfillment_task_id: task.id)

    expect(result.data.awb_number).to be_present
    expect(task.reload.shipping_label.awb_number).to eq(result.data.awb_number)
  end
end
