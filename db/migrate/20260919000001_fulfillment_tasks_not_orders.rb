# foreign keys are worth keeping, and `returns` / `shipping_labels` already point here.
class FulfillmentTasksNotOrders < ActiveRecord::Migration[8.0]
  TASK_STATUSES = %w[received picking packed cancelled].freeze

  def up
    rename_table :orders, :fulfillment_tasks
    rename_table :order_items, :fulfillment_task_lines

    rename_column :fulfillment_task_lines, :order_id, :fulfillment_task_id
    rename_column :returns, :order_id, :fulfillment_task_id
    rename_column :shipping_labels, :order_id, :fulfillment_task_id

    execute <<~SQL.squish
      UPDATE fulfillment_tasks SET status = 'received' WHERE status IN ('next_day', 'pending') OR status IS NULL
    SQL
    execute <<~SQL.squish
      UPDATE fulfillment_tasks SET status = 'packed' WHERE status IN ('dispatched', 'in_transit', 'delivered')
    SQL
    execute <<~SQL.squish
      UPDATE fulfillment_tasks SET status = 'received'
      WHERE status NOT IN (#{TASK_STATUSES.map { |s| "'#{s}'" }.join(', ')})
    SQL

    change_column_null :fulfillment_tasks, :status, false
    add_check_constraint :fulfillment_tasks,
      "status IN (#{TASK_STATUSES.map { |s| "'#{s}'" }.join(', ')})",
      name: "fulfillment_tasks_status_is_a_picking_state"

    remove_column :fulfillment_tasks, :buyer_name
    remove_column :fulfillment_tasks, :buyer_phone
    remove_column :fulfillment_tasks, :shipping_address
    remove_column :fulfillment_tasks, :total_amount

    remove_column :fulfillment_task_lines, :product_name
    remove_column :fulfillment_task_lines, :price
  end

  def down
    add_column :fulfillment_task_lines, :price, :decimal
    add_column :fulfillment_task_lines, :product_name, :string
    add_column :fulfillment_tasks, :total_amount, :decimal
    add_column :fulfillment_tasks, :shipping_address, :text
    add_column :fulfillment_tasks, :buyer_phone, :string
    add_column :fulfillment_tasks, :buyer_name, :string

    remove_check_constraint :fulfillment_tasks, name: "fulfillment_tasks_status_is_a_picking_state"
    change_column_null :fulfillment_tasks, :status, true

    rename_column :shipping_labels, :fulfillment_task_id, :order_id
    rename_column :returns, :fulfillment_task_id, :order_id
    rename_column :fulfillment_task_lines, :fulfillment_task_id, :order_id

    rename_table :fulfillment_task_lines, :order_items
    rename_table :fulfillment_tasks, :orders
  end
end
