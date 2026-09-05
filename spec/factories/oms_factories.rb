# typed: false

FactoryBot.define do
  factory :merchant do
    sequence(:name) { |n| "Boutique #{n}" }
    sequence(:code) { |n| "BTQ#{n}" }
    cutoff_hour { 14 }
  end

  factory :order do
    merchant
    sequence(:order_number) { |n| "ORD-#{n}" }
    buyer_name { "Jane Doe" }
    buyer_phone { "08123456789" }
    shipping_address { "Jl. Sudirman No. 1, Jakarta" }
    total_amount { BigDecimal("150000.0") }
    status { "received" }
    same_day_cutoff_at { Time.current + 2.hours }
  end

  factory :order_item do
    order
    sku { "GAMIS-RED-M" }
    product_name { "Gamis Modern Red M" }
    quantity { 1 }
    price { BigDecimal("150000.0") }
  end

  factory :shipping_label do
    order
    sequence(:awb_number) { |n| "AWB-100#{n}" }
    pdf_url { "/labels/test.pdf" }
    reprint_count { 1 }
  end

  factory :return do
    merchant
    order
    reason { "Wrong Size" }
    status { "requested" }
  end
end
