# typed: strict
# frozen_string_literal: true

class RenameMerchantsToFulfillmentSettings < ActiveRecord::Migration[8.1]
  TABLES = %i[fulfillment_tasks stock_operations stock_reservations].freeze

  def up
    unlinked = select_values("SELECT id FROM merchants WHERE principal_id IS NULL ORDER BY id")
    if unlinked.any?
      raise "merchants rows without a principal_id cannot be carried over to fulfillment_settings: #{unlinked.join(', ')}"
    end

    TABLES.each do |table|
      add_column table, :merchant_principal_id, :uuid
      execute <<~SQL
        UPDATE #{table} AS target
        SET merchant_principal_id = merchants.principal_id
        FROM merchants
        WHERE target.merchant_id = merchants.id
      SQL
      change_column_null table, :merchant_principal_id, false
      remove_foreign_key table, :merchants
    end

    remove_index :fulfillment_tasks, name: "index_fulfillment_tasks_on_merchant_id_and_order_number"
    remove_index :fulfillment_tasks, name: "index_fulfillment_tasks_on_merchant_id_and_same_day_cutoff_at"
    remove_index :fulfillment_tasks, name: "index_fulfillment_tasks_on_merchant_id"
    remove_column :fulfillment_tasks, :merchant_id

    remove_index :stock_operations, name: "index_stock_operations_on_merchant_operation_and_key"
    remove_index :stock_operations, name: "index_stock_operations_on_merchant_id"
    remove_column :stock_operations, :merchant_id

    remove_index :stock_reservations, name: "index_stock_reservations_on_merchant_order_and_sku"
    remove_index :stock_reservations, name: "index_stock_reservations_on_merchant_id"
    remove_column :stock_reservations, :merchant_id

    rename_table :merchants, :fulfillment_settings
    rename_column :fulfillment_settings, :principal_id, :merchant_principal_id
    change_column_null :fulfillment_settings, :merchant_principal_id, false
    execute <<~SQL
      ALTER INDEX IF EXISTS index_merchants_on_principal_id
      RENAME TO index_fulfillment_settings_on_merchant_principal_id
    SQL
    execute <<~SQL
      ALTER TABLE fulfillment_settings
      RENAME CONSTRAINT merchants_cutoff_hour_is_an_hour
      TO fulfillment_settings_cutoff_hour_is_an_hour
    SQL

    add_index :fulfillment_tasks, %i[merchant_principal_id order_number],
              unique: true,
              name: "index_fulfillment_tasks_on_merchant_principal_id_and_order"
    add_index :fulfillment_tasks, %i[merchant_principal_id same_day_cutoff_at],
              name: "index_fulfillment_tasks_on_merchant_principal_id_and_cutoff"
    add_index :fulfillment_tasks, :merchant_principal_id,
              name: "index_fulfillment_tasks_on_merchant_principal_id"

    add_index :stock_operations, %i[merchant_principal_id operation idempotency_key],
              unique: true,
              name: "index_stock_operations_on_merchant_operation_and_key"
    add_index :stock_operations, :merchant_principal_id,
              name: "index_stock_operations_on_merchant_principal_id"

    add_index :stock_reservations, %i[merchant_principal_id order_number sku],
              unique: true,
              name: "index_stock_reservations_on_merchant_order_and_sku"
    add_index :stock_reservations, :merchant_principal_id,
              name: "index_stock_reservations_on_merchant_principal_id"

    TABLES.each do |table|
      add_foreign_key table, :fulfillment_settings,
                      column: :merchant_principal_id,
                      primary_key: :merchant_principal_id
    end
  end

  def down
    TABLES.each do |table|
      remove_foreign_key table, column: :merchant_principal_id
    end

    remove_index :fulfillment_tasks, name: "index_fulfillment_tasks_on_merchant_principal_id_and_order"
    remove_index :fulfillment_tasks, name: "index_fulfillment_tasks_on_merchant_principal_id_and_cutoff"
    remove_index :fulfillment_tasks, name: "index_fulfillment_tasks_on_merchant_principal_id"

    remove_index :stock_operations, name: "index_stock_operations_on_merchant_operation_and_key"
    remove_index :stock_operations, name: "index_stock_operations_on_merchant_principal_id"

    remove_index :stock_reservations, name: "index_stock_reservations_on_merchant_order_and_sku"
    remove_index :stock_reservations, name: "index_stock_reservations_on_merchant_principal_id"

    execute <<~SQL
      ALTER TABLE fulfillment_settings
      RENAME CONSTRAINT fulfillment_settings_cutoff_hour_is_an_hour
      TO merchants_cutoff_hour_is_an_hour
    SQL
    execute <<~SQL
      ALTER INDEX IF EXISTS index_fulfillment_settings_on_merchant_principal_id
      RENAME TO index_merchants_on_principal_id
    SQL
    change_column_null :fulfillment_settings, :merchant_principal_id, true
    rename_column :fulfillment_settings, :merchant_principal_id, :principal_id
    rename_table :fulfillment_settings, :merchants

    TABLES.each do |table|
      add_column table, :merchant_id, :bigint
      execute <<~SQL
        UPDATE #{table} AS target
        SET merchant_id = merchants.id
        FROM merchants
        WHERE target.merchant_principal_id = merchants.principal_id
      SQL
      change_column_null table, :merchant_id, false
      remove_column table, :merchant_principal_id
      add_foreign_key table, :merchants
    end

    add_index :fulfillment_tasks, %i[merchant_id order_number],
              unique: true,
              name: "index_fulfillment_tasks_on_merchant_id_and_order_number"
    add_index :fulfillment_tasks, %i[merchant_id same_day_cutoff_at],
              name: "index_fulfillment_tasks_on_merchant_id_and_same_day_cutoff_at"
    add_index :fulfillment_tasks, :merchant_id,
              name: "index_fulfillment_tasks_on_merchant_id"

    add_index :stock_operations, %i[merchant_id operation idempotency_key],
              unique: true,
              name: "index_stock_operations_on_merchant_operation_and_key"
    add_index :stock_operations, :merchant_id,
              name: "index_stock_operations_on_merchant_id"

    add_index :stock_reservations, %i[merchant_id order_number sku],
              unique: true,
              name: "index_stock_reservations_on_merchant_order_and_sku"
    add_index :stock_reservations, :merchant_id,
              name: "index_stock_reservations_on_merchant_id"
  end
end
