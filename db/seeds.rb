# typed: false

# db/seeds.rb

require "securerandom"

if Rails.env.production? && ENV["ALLOW_DESTRUCTIVE_SEED"] != "yes"
  abort <<~MSG
    Refusing to seed in production: this script calls destroy_all on orders, labels,
    returns, staff and merchants, and installs demo accounts.
    Set ALLOW_DESTRUCTIVE_SEED=yes only if you genuinely intend to wipe this database.
  MSG
end

SEED_STAFF_PASSWORD = ENV.fetch("SEED_STAFF_PASSWORD") { SecureRandom.urlsafe_base64(18) }

puts "🌱 Clearing old records and seeding Fashion Fulfillment OMS with Logic-Driven Seeder..."

# 1. Clean Database (Reset old data)
# -------------------------------------------------------------
OrderItem.destroy_all
ShippingLabel.destroy_all
Return.destroy_all
Order.destroy_all
StaffUser.destroy_all
Merchant.destroy_all

MERCHANTS_DATA = [
  { code: "BH-001", name: "Boutique Hijab Premium", cutoff_hour: 14, manager_name: "Budi Hendra", manager_email: "budi@boutiquehijab.id", role: "Warehouse Lead Manager" },
  { code: "GES-002", name: "Gamis Elegant Style", cutoff_hour: 15, manager_name: "Siti Nurhaliza", manager_email: "siti@gamiselegant.id", role: "Fulfillment Logistics Manager" }
].freeze

CATALOG_ITEMS = [
  { sku: "BH-SLK-NVY", name: "Premium Silk Hijab (Navy)", price: 350000.0, rack: "A", bin: 12 },
  { sku: "HJB-PSH-BLK", name: "Hijab Pashmina Silk Black", price: 100000.0, rack: "A", bin: 13 },
  { sku: "BH-CTN-BLK", name: "Everyday Cotton Hijab (Black)", price: 140000.0, rack: "B", bin: 5 },
  { sku: "BH-CHF-EMR", name: "Chiffon Evening Wrap (Emerald)", price: 520000.0, rack: "C", bin: 8 },
  { sku: "HJB-SLK-SLV", name: "Hijab Silk Silver Premium", price: 160000.0, rack: "A", bin: 1 },
  { sku: "GMS-EMR-XL", name: "Gamis Velvet Emerald XL", price: 680000.0, rack: "D", bin: 1 },
  { sku: "KKO-MDR-M", name: "Koko Modern Slim Fit M", price: 390000.0, rack: "E", bin: 10 }
].freeze

BUYER_PERSONAS = [
  { name: "Sarah Jane", phone: "081234567890", address: "124 Maple Street, Apt 4B, Brooklyn, NY 11201" },
  { name: "Michael Chen", phone: "082345678901", address: "789 Pine Road, Suite 200, Seattle, WA 98101" },
  { name: "Emma Watson", phone: "083456789012", address: "456 Oak Lane, Austin, TX 78701" },
  { name: "Rina Anggraini", phone: "081987654321", address: "Jl. Cikini Raya No. 99, Jakarta Pusat" },
  { name: "Anisa Fitri", phone: "084567890123", address: "Jl. Malioboro No. 88, Yogyakarta" },
  { name: "Dewi Sartika", phone: "085678901234", address: "Jl. Pemuda No. 101, Surabaya" }
].freeze

STATUS_PIPELINE = [ "received", "packing", "packed", "dispatched", "in_transit", "delivered" ].freeze

# 2. Logic Step: Seed Merchants & Staff Users
# -------------------------------------------------------------
created_merchants = MERCHANTS_DATA.map do |data|
  merchant = Merchant.create!(
    code: data[:code],
    name: data[:name],
    cutoff_hour: data[:cutoff_hour]
  )

  StaffUser.create!(
    merchant: merchant,
    email: data[:manager_email],
    name: data[:manager_name],
    role: data[:role],
    password: SEED_STAFF_PASSWORD
  )


  merchant
end

puts "✅ #{created_merchants.size} Merchants and Staff Users seeded."

# 3. Logic Step: Seed Orders with Item Matrix & Dynamic Calculation
# -------------------------------------------------------------
now = Time.current

created_merchants.each_with_index do |merchant, m_idx|
  merchant_catalog = m_idx.zero? ? CATALOG_ITEMS.take(5) : CATALOG_ITEMS.drop(4)
  sla_cutoff_offsets = [ -1.hour, 30.minutes, 4.hours, 2.hours, -2.hours ]

  BUYER_PERSONAS.each_with_index do |buyer, b_idx|
    order_num_seq = 1000 + b_idx + (m_idx * 100)
    order_number = "ORD-#{merchant.code}-#{order_num_seq}"

    status = STATUS_PIPELINE[b_idx % STATUS_PIPELINE.size]
    cutoff_time = now + sla_cutoff_offsets[b_idx % sla_cutoff_offsets.size]

    selected_catalog_items = merchant_catalog.sample((b_idx % 2) + 1)
    computed_total = selected_catalog_items.sum { |i| i[:price] }

    order = Order.create!(
      merchant: merchant,
      order_number: order_number,
      buyer_name: buyer[:name],
      buyer_phone: buyer[:phone],
      shipping_address: buyer[:address],
      status: status,
      total_amount: BigDecimal(computed_total.to_s),
      same_day_cutoff_at: cutoff_time
    )

    selected_catalog_items.each do |cat|
      order.order_items.create!(
        sku: cat[:sku],
        product_name: cat[:name],
        quantity: 1,
        price: BigDecimal(cat[:price].to_s),
        bin_location: "Rak #{cat[:rack]}-01, Bin #{cat[:bin]}"
      )
    end

    if [ "packed", "dispatched", "in_transit", "delivered" ].include?(status)
      ShippingLabel.create!(
        order: order,
        awb_number: "TRK-#{order.id}#{order_num_seq}-XYZ",
        pdf_url: "/labels/TRK-#{order.id}#{order_num_seq}-XYZ.pdf",
        reprint_count: 1
      )
    end

    if status == "delivered"
      Return.create!(
        merchant: merchant,
        order: order,
        reason: "Size exchange requested for #{selected_catalog_items.first[:name]}",
        status: "requested"
      )
    end
  end
end

puts "🎉 Database successfully reset & seeded with new logic-driven records!"
puts
puts "Staff password for this run (shown once, not stored anywhere else):"
puts "  #{SEED_STAFF_PASSWORD}"
puts "Merchants have no API key. The JSON API takes an identity access token, and a merchant is"
puts "reachable only once its principal_id is linked to the identity principal that owns it:"
puts "  bin/rails runner 'Merchant.pluck(:code, :principal_id).each { |c, p| puts \"#{'%s'} #{'%s'}\" % [c, p || \"(unlinked)\"] }'"
