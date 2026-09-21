# typed: false

# Demo data for a warehouse, and nothing that belongs to another service.
#
# What this file used to do, and no longer can: it created Orders with buyer_name, buyer_phone and
# shipping_address, OrderItems with product_name and price, and StaffUsers with bcrypt passwords. All
# five of those were other services' data — the buyer is identity's, the order is order's, the
# product is catalog's, the price is pricing's, the credential is identity's — and W4 and W1 removed
# them. The file kept referring to the deleted classes, so it had stopped running at all.
#
# A fulfillment task is what is left when none of that is yours: an order number to quote back, a SKU
# to pick, a quantity, a bin, and a cutoff to beat.

require "securerandom"

if Rails.env.production? && ENV["ALLOW_DESTRUCTIVE_SEED"] != "yes"
  abort <<~MSG
    Refusing to seed in production: this script calls destroy_all on fulfillment tasks, labels,
    returns and merchants.
    Set ALLOW_DESTRUCTIVE_SEED=yes only if you genuinely intend to wipe this database.
  MSG
end

puts "🌱 Clearing old records and seeding the warehouse..."

ShippingLabel.destroy_all
FulfillmentTaskLine.destroy_all
FulfillmentTask.destroy_all
Merchant.destroy_all

MERCHANTS_DATA = [
  { principal_id: "11111111-1111-4111-8111-111111111111", cutoff_hour: 14 },
  { principal_id: "22222222-2222-4222-8222-222222222222", cutoff_hour: 15 }
].freeze

# SKUs only. The product behind a SKU — its name, its price, whether it still exists — is catalog's
# to know, and a warehouse that stores a second copy of it stores a copy that goes stale.
SKUS = [
  { sku: "BH-SLK-NVY", rack: "A", bin: 12 },
  { sku: "HJB-PSH-BLK", rack: "A", bin: 13 },
  { sku: "BH-CTN-BLK", rack: "B", bin: 5 },
  { sku: "BH-CHF-EMR", rack: "C", bin: 8 },
  { sku: "HJB-SLK-SLV", rack: "A", bin: 1 },
  { sku: "GMS-EMR-XL", rack: "D", bin: 1 },
  { sku: "KKO-MDR-M", rack: "E", bin: 10 }
].freeze

# Every state a task can actually be in. `dispatched`, `in_transit` and `delivered` used to be seeded
# here; they are not packing states, the database check constraint rejects them, and what happens to
# a parcel after it leaves the building is matching's to say.
STATUSES = FulfillmentTask::STATUSES.freeze

created_merchants = MERCHANTS_DATA.map do |data|
  Merchant.create!(principal_id: data[:principal_id], cutoff_hour: data[:cutoff_hour])
end

puts "✅ #{created_merchants.size} merchants seeded."

now = Time.current
task_count = 0

created_merchants.each_with_index do |merchant, m_idx|
  merchant_skus = m_idx.zero? ? SKUS.take(5) : SKUS.drop(4)

  # A spread of cutoffs, two of them already past, so an SLA display has something overdue to show.
  sla_cutoff_offsets = [ -1.hour, 30.minutes, 4.hours, 2.hours, -2.hours, 6.hours ]

  6.times do |t_idx|
    status = STATUSES[t_idx % STATUSES.size]

    task = FulfillmentTask.create!(
      merchant: merchant,
      order_number: "ORD-#{merchant.id}-#{1000 + t_idx + (m_idx * 100)}",
      status: status,
      same_day_cutoff_at: now + sla_cutoff_offsets[t_idx % sla_cutoff_offsets.size]
    )
    task_count += 1

    merchant_skus.sample((t_idx % 2) + 1).each do |item|
      task.fulfillment_task_lines.create!(
        sku: item[:sku],
        quantity: 1,
        bin_location: "Rak #{item[:rack]}-01, Bin #{item[:bin]}"
      )
    end

    # A label exists once the parcel is packed, not before.
    if status == "packed"
      ShippingLabel.create!(
        fulfillment_task: task,
        awb_number: "TRK-#{task.id}-#{SecureRandom.hex(3).upcase}",
        reprint_count: 0
      )
    end
  end
end

puts "🎉 #{task_count} fulfillment tasks seeded across #{created_merchants.size} merchants."
puts
puts "There is no sign-in here: this service has no pages and no accounts. The JSON API takes an"
puts "identity access token, and a merchant is reachable only once its principal_id is linked to the"
puts "identity principal that owns it:"
puts %q(  bin/rails runner 'Merchant.pluck(:id, :principal_id).each { |i, p| puts format("%s %s", i, p || "(unlinked)") }')
