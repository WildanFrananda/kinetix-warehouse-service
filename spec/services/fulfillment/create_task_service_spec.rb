# typed: false

require "rails_helper"

RSpec.describe Fulfillment::CreateTaskService do
  let(:jakarta) { ActiveSupport::TimeZone["Asia/Jakarta"] }
  let!(:merchant) { create(:merchant, cutoff_hour: 14) }

  def create_task(order_number: "ORD-CUTOFF", time_zone: jakarta)
    service = described_class.new(
      merchant_repository: MerchantRepository.new,
      task_repository: FulfillmentTaskRepository.new,
      reservation_repository: StockReservationRepository.new,
      time_zone: time_zone
    )
    form = Fulfillment::CreateTaskForm.new(
      order_number: order_number,
      lines: [ Fulfillment::CreateTaskForm::LineInput.new(sku: "SKU-1", quantity: 1) ]
    )

    service.call(merchant_id: merchant.id, form: form)
  end

  it "reads the merchant's cutoff hour on the platform's clock, not on UTC's" do
    travel_to(Time.utc(2026, 10, 21, 6, 0, 0)) do
      result = create_task

      expect(result.data.same_day_cutoff_at).to eq(jakarta.local(2026, 10, 21, 14, 0, 0))
    end
  end

  it "rolls to the next day once the cutoff has passed on the platform's clock" do
    travel_to(Time.utc(2026, 10, 21, 7, 30, 0)) do
      result = create_task

      expect(result.data.same_day_cutoff_at).to eq(jakarta.local(2026, 10, 22, 14, 0, 0))
    end
  end
end
