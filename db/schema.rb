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

ActiveRecord::Schema[8.1].define(version: 2026_09_19_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "bin_inventories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "merchant_principal_id"
    t.integer "quantity", default: 0, null: false
    t.integer "reserved_quantity", default: 0, null: false
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.bigint "warehouse_bin_id", null: false
    t.index ["merchant_principal_id", "sku"], name: "index_bin_inventories_on_merchant_principal_id_and_sku"
    t.index ["sku"], name: "index_bin_inventories_on_sku"
    t.index ["warehouse_bin_id"], name: "index_bin_inventories_on_warehouse_bin_id"
  end

  create_table "fulfillment_task_lines", force: :cascade do |t|
    t.string "bin_location"
    t.datetime "created_at", null: false
    t.bigint "fulfillment_task_id", null: false
    t.integer "quantity"
    t.string "sku"
    t.datetime "updated_at", null: false
    t.index ["fulfillment_task_id"], name: "index_fulfillment_task_lines_on_fulfillment_task_id"
  end

  create_table "fulfillment_tasks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "merchant_id", null: false
    t.string "order_number"
    t.datetime "same_day_cutoff_at"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["merchant_id", "order_number"], name: "index_fulfillment_tasks_on_merchant_id_and_order_number", unique: true
    t.index ["merchant_id", "same_day_cutoff_at"], name: "index_fulfillment_tasks_on_merchant_id_and_same_day_cutoff_at"
    t.index ["merchant_id"], name: "index_fulfillment_tasks_on_merchant_id"
    t.check_constraint "status::text = ANY (ARRAY['received'::character varying, 'packing'::character varying, 'packed'::character varying, 'cancelled'::character varying]::text[])", name: "fulfillment_tasks_status_is_a_packing_state"
  end

  create_table "merchants", force: :cascade do |t|
    t.string "code"
    t.datetime "created_at", null: false
    t.integer "cutoff_hour"
    t.decimal "latitude", precision: 10, scale: 6, default: "-6.2088", null: false
    t.decimal "longitude", precision: 10, scale: 6, default: "106.8456", null: false
    t.string "name"
    t.uuid "principal_id"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_merchants_on_code", unique: true
    t.index ["principal_id"], name: "index_merchants_on_principal_id", unique: true
  end

  create_table "returns", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "fulfillment_task_id", null: false
    t.bigint "merchant_id", null: false
    t.string "reason"
    t.datetime "resolved_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["fulfillment_task_id"], name: "index_returns_on_fulfillment_task_id"
    t.index ["merchant_id"], name: "index_returns_on_merchant_id"
  end

  create_table "shipping_labels", force: :cascade do |t|
    t.string "awb_number"
    t.datetime "created_at", null: false
    t.bigint "fulfillment_task_id", null: false
    t.string "pdf_url"
    t.integer "reprint_count"
    t.datetime "updated_at", null: false
    t.index ["awb_number"], name: "index_shipping_labels_on_awb_number", unique: true
    t.index ["fulfillment_task_id"], name: "index_shipping_labels_on_fulfillment_task_id"
  end

  create_table "staff_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.bigint "merchant_id", null: false
    t.string "name"
    t.string "password_digest"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["merchant_id"], name: "index_staff_users_on_merchant_id"
  end

  create_table "stock_adjustments", force: :cascade do |t|
    t.uuid "adjusted_by_principal_id", null: false
    t.datetime "created_at", null: false
    t.string "idempotency_key", limit: 255, null: false
    t.uuid "merchant_principal_id", null: false
    t.string "note"
    t.integer "quantity_after", null: false
    t.integer "quantity_before", null: false
    t.integer "quantity_delta", null: false
    t.string "reason", limit: 32, null: false
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.bigint "warehouse_bin_id", null: false
    t.index ["idempotency_key"], name: "index_stock_adjustments_on_idempotency_key", unique: true
    t.index ["sku", "created_at"], name: "index_stock_adjustments_on_sku_and_created_at"
    t.index ["warehouse_bin_id"], name: "index_stock_adjustments_on_warehouse_bin_id"
    t.check_constraint "quantity_delta <> 0", name: "stock_adjustments_delta_not_zero"
    t.check_constraint "reason::text = ANY (ARRAY['DAMAGE'::character varying, 'SHRINKAGE'::character varying, 'MISCOUNT'::character varying, 'RETURN_TO_SUPPLIER'::character varying, 'EXPIRY'::character varying]::text[])", name: "stock_adjustments_reason_known"
  end

  create_table "stock_operations", force: :cascade do |t|
    t.boolean "applied", default: false, null: false
    t.integer "conflict_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "first_request_id", default: "", null: false
    t.string "idempotency_key", limit: 255, null: false
    t.string "last_replay_request_id"
    t.bigint "merchant_id", null: false
    t.string "operation", limit: 16, null: false
    t.string "order_number", limit: 64, null: false
    t.integer "quantity", null: false
    t.integer "replay_count", default: 0, null: false
    t.integer "replay_refused_count", default: 0, null: false
    t.string "request_digest", limit: 64, null: false
    t.binary "response", null: false
    t.string "sku", limit: 128, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_stock_operations_on_created_at"
    t.index ["merchant_id", "operation", "idempotency_key"], name: "index_stock_operations_on_merchant_operation_and_key", unique: true
    t.index ["merchant_id"], name: "index_stock_operations_on_merchant_id"
    t.index ["order_number"], name: "index_stock_operations_on_order_number"
  end

  create_table "stock_receipts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "idempotency_key", limit: 255, null: false
    t.uuid "merchant_principal_id"
    t.string "note"
    t.integer "quantity", null: false
    t.uuid "received_by_principal_id", null: false
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.bigint "warehouse_bin_id", null: false
    t.index ["idempotency_key"], name: "index_stock_receipts_on_idempotency_key", unique: true
    t.index ["sku"], name: "index_stock_receipts_on_sku"
    t.index ["warehouse_bin_id"], name: "index_stock_receipts_on_warehouse_bin_id"
    t.check_constraint "quantity > 0", name: "stock_receipts_quantity_positive"
  end

  create_table "stock_reservations", force: :cascade do |t|
    t.bigint "bin_inventory_id"
    t.datetime "created_at", null: false
    t.bigint "merchant_id", null: false
    t.string "order_number", limit: 64, null: false
    t.integer "quantity", null: false
    t.datetime "released_at"
    t.string "sku", limit: 128, null: false
    t.datetime "updated_at", null: false
    t.index ["bin_inventory_id"], name: "index_stock_reservations_on_bin_inventory_id"
    t.index ["merchant_id", "order_number", "sku"], name: "index_stock_reservations_on_merchant_order_and_sku", unique: true
    t.index ["merchant_id"], name: "index_stock_reservations_on_merchant_id"
    t.index ["sku"], name: "index_stock_reservations_on_sku"
  end

  create_table "warehouse_bins", force: :cascade do |t|
    t.string "bin_code", null: false
    t.datetime "created_at", null: false
    t.integer "shelf_level", default: 1, null: false
    t.datetime "updated_at", null: false
    t.string "zone", null: false
    t.index ["bin_code"], name: "index_warehouse_bins_on_bin_code", unique: true
  end

  add_foreign_key "bin_inventories", "warehouse_bins"
  add_foreign_key "fulfillment_task_lines", "fulfillment_tasks"
  add_foreign_key "fulfillment_tasks", "merchants"
  add_foreign_key "returns", "fulfillment_tasks"
  add_foreign_key "returns", "merchants"
  add_foreign_key "shipping_labels", "fulfillment_tasks"
  add_foreign_key "staff_users", "merchants"
  add_foreign_key "stock_adjustments", "warehouse_bins"
  add_foreign_key "stock_operations", "merchants"
  add_foreign_key "stock_receipts", "warehouse_bins"
  add_foreign_key "stock_reservations", "merchants"
end
