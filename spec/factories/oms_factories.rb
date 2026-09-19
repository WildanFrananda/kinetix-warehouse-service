# typed: false

FactoryBot.define do
  factory :merchant do
    sequence(:name) { |n| "Boutique #{n}" }
    sequence(:code) { |n| "BTQ#{n}" }
    cutoff_hour { 14 }
  end

  factory :fulfillment_task do
    merchant
    sequence(:order_number) { |n| "ORD-#{n}" }
    status { "received" }
    same_day_cutoff_at { Time.current + 2.hours }
  end

  factory :fulfillment_task_line do
    fulfillment_task
    sku { "GAMIS-RED-M" }
    quantity { 1 }
  end

  factory :shipping_label do
    fulfillment_task
    sequence(:awb_number) { |n| "AWB-100#{n}" }
    pdf_url { "/labels/test.pdf" }
    reprint_count { 1 }
  end

  factory :return do
    merchant
    fulfillment_task
    reason { "Wrong Size" }
    status { "requested" }
  end
end
