# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.

ActiveRecord::Schema[8.1].define(version: 2026_08_21_160000) do
  enable_extension "pg_catalog.plpgsql"

  create_table "merchants", force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.string "api_key", null: false
    t.integer "cutoff_hour", default: 14
    t.decimal "latitude", precision: 10, scale: 6, default: "-6.2088"
    t.decimal "longitude", precision: 10, scale: 6, default: "106.8456"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "staff_users", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "warehouse_bins", force: :cascade do |t|
    t.string "bin_code", null: false
    t.string "zone", null: false
    t.integer "shelf_level", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bin_code"], name: "index_warehouse_bins_on_bin_code", unique: true
  end

  create_table "bin_inventories", force: :cascade do |t|
    t.bigint "warehouse_bin_id", null: false
    t.string "sku", null: false
    t.integer "quantity", default: 0, null: false
    t.integer "reserved_quantity", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sku"], name: "index_bin_inventories_on_sku"
    t.index ["warehouse_bin_id"], name: "index_bin_inventories_on_warehouse_bin_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.string "order_number"
    t.string "buyer_name"
    t.string "buyer_phone"
    t.text "shipping_address"
    t.decimal "total_amount"
    t.string "status"
    t.datetime "same_day_cutoff_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_orders_on_merchant_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "sku"
    t.string "product_name"
    t.integer "quantity"
    t.decimal "price"
    t.string "bin_location"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "shipping_labels", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.string "awb_number"
    t.string "pdf_url"
    t.string "tracking_number"
    t.integer "reprint_count", default: 0
    t.datetime "printed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_shipping_labels_on_order_id"
  end

  create_table "returns", force: :cascade do |t|
    t.bigint "merchant_id", null: false
    t.bigint "order_id", null: false
    t.string "reason"
    t.string "status"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_returns_on_merchant_id"
    t.index ["order_id"], name: "index_returns_on_order_id"
  end
end
