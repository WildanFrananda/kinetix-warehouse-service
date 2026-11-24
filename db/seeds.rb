# typed: false

require "securerandom"

if Rails.env.production? && ENV["ALLOW_DESTRUCTIVE_SEED"] != "yes"
  abort <<~MSG
    Refusing to seed in production: this script calls destroy_all on fulfillment tasks, labels,
    returns and fulfillment settings.
    Set ALLOW_DESTRUCTIVE_SEED=yes only if you genuinely intend to wipe this database.
  MSG
end

puts "🌱 Clearing old records and seeding the warehouse..."

ShippingLabel.destroy_all
FulfillmentTaskLine.destroy_all
FulfillmentTask.destroy_all
FulfillmentSetting.destroy_all

SETTINGS_DATA = [
  { merchant_principal_id: "11111111-1111-4111-8111-111111111111", cutoff_hour: 14 },
  { merchant_principal_id: "22222222-2222-4222-8222-222222222222", cutoff_hour: 15 }
].freeze

SKUS = [
  { sku: "BH-SLK-NVY", rack: "A", bin: 12 },
  { sku: "HJB-PSH-BLK", rack: "A", bin: 13 },
  { sku: "BH-CTN-BLK", rack: "B", bin: 5 },
  { sku: "BH-CHF-EMR", rack: "C", bin: 8 },
  { sku: "HJB-SLK-SLV", rack: "A", bin: 1 },
  { sku: "GMS-EMR-XL", rack: "D", bin: 1 },
  { sku: "KKO-MDR-M", rack: "E", bin: 10 }
].freeze

STATUSES = FulfillmentTask::STATUSES.freeze

created_settings = SETTINGS_DATA.map do |data|
  FulfillmentSetting.create!(
    merchant_principal_id: data[:merchant_principal_id],
    cutoff_hour: data[:cutoff_hour]
  )
end

puts "✅ #{created_settings.size} fulfillment settings seeded."

now = Time.current
task_count = 0

created_settings.each_with_index do |setting, m_idx|
  merchant_skus = m_idx.zero? ? SKUS.take(5) : SKUS.drop(4)

  sla_cutoff_offsets = [ -1.hour, 30.minutes, 4.hours, 2.hours, -2.hours, 6.hours ]

  6.times do |t_idx|
    status = STATUSES[t_idx % STATUSES.size]

    task = FulfillmentTask.create!(
      fulfillment_setting: setting,
      order_number: "ORD-#{setting.id}-#{1000 + t_idx + (m_idx * 100)}",
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

    if status == "packed"
      ShippingLabel.create!(
        fulfillment_task: task,
        awb_number: "TRK-#{task.id}-#{SecureRandom.hex(3).upcase}",
        reprint_count: 0
      )
    end
  end
end

puts "🎉 #{task_count} fulfillment tasks seeded across #{created_settings.size} fulfillment settings."
puts
puts "There is no sign-in here: this service has no pages and no accounts. The JSON API takes an"
puts "identity access token, and a merchant's setting is keyed by its merchant_principal_id:"
puts %q(  bin/rails runner 'FulfillmentSetting.pluck(:id, :merchant_principal_id).each { |i, p| puts format("%s %s", i, p) }')
