# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_21_160000) do
  enable_extension "pg_catalog.plpgsql"

  create_table "bin_inventories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "quantity", default: 0, null: false
    t.integer "reserved_quantity", default: 0, null: false
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.bigint "warehouse_bin_id", null: false
    t.index ["sku"], name: "index_bin_inventories_on_sku"
    t.index ["warehouse_bin_id"], name: "index_bin_inventories_on_warehouse_bin_id"
  end

  create_table "merchants", force: :cascade do |t|
    t.string "api_key", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "cutoff_hour", default: 14
    t.decimal "latitude", precision: 10, scale: 6, default: "-6.2088"
    t.decimal "longitude", precision: 10, scale: 6, default: "106.8456"
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "order_items", force: :cascade do |t|
    t.string "bin_location"
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.decimal "price"
    t.string "product_name"
    t.integer "quantity"
    t.string "sku"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "buyer_name"
    t.string "buyer_phone"
    t.datetime "created_at", null: false
    t.bigint "merchant_id", null: false
    t.string "order_number"
    t.datetime "same_day_cutoff_at"
    t.text "shipping_address"
    t.string "status"
    t.decimal "total_amount"
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_orders_on_merchant_id"
  end

  create_table "returns", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "merchant_id", null: false
    t.bigint "order_id", null: false
    t.string "reason"
    t.datetime "resolved_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_returns_on_merchant_id"
    t.index ["order_id"], name: "index_returns_on_order_id"
  end

  create_table "shipping_labels", force: :cascade do |t|
    t.string "awb_number"
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.string "pdf_url"
    t.datetime "printed_at"
    t.integer "reprint_count", default: 0
    t.string "tracking_number"
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_shipping_labels_on_order_id"
  end

  create_table "staff_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "merchant_id", null: false
    t.string "name", null: false
    t.string "password_digest"
    t.string "role", null: false
    t.datetime "updated_at", null: false
  end

  create_table "warehouse_bins", force: :cascade do |t|
    t.string "bin_code", null: false
    t.datetime "created_at", null: false
    t.integer "shelf_level", default: 1, null: false
    t.datetime "updated_at", null: false
    t.string "zone", null: false
    t.index ["bin_code"], name: "index_warehouse_bins_on_bin_code", unique: true
  end
end
