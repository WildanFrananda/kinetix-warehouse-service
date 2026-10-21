# typed: strict
# frozen_string_literal: true

class OneInventoryRowPerBinAndSku < ActiveRecord::Migration[8.1]
  INDEX = "index_bin_inventories_on_warehouse_bin_id_and_sku"

  DUPLICATES = <<~SQL
    SELECT warehouse_bin_id,
           sku,
           min(id) AS keeper,
           array_agg(id ORDER BY id) AS ids,
           array_agg(COALESCE(merchant_principal_id::text, 'no owner') ORDER BY id) AS owners,
           count(DISTINCT COALESCE(merchant_principal_id::text, '')) AS owner_count,
           sum(quantity) AS quantity,
           sum(reserved_quantity) AS reserved_quantity,
           min(created_at) AS created_at
    FROM bin_inventories
    GROUP BY warehouse_bin_id, sku
    HAVING count(*) > 1
  SQL

  def up
    groups = select_all(DUPLICATES).to_a
    contested = groups.reject { |group| group["owner_count"].to_i == 1 }
    raise refusal(contested) if contested.any?

    merge(groups) if groups.any?

    add_index :bin_inventories, %i[warehouse_bin_id sku], unique: true, name: INDEX, if_not_exists: true
  end

  def down
    remove_index :bin_inventories, name: INDEX, if_exists: true
  end

  private

  def merge(groups)
    say "merging #{groups.size} bin and sku pairs held on more than one row by the same owner"

    execute <<~SQL
      WITH duplicates AS (#{DUPLICATES})
      UPDATE stock_reservations AS reservation
      SET bin_inventory_id = duplicates.keeper, updated_at = now()
      FROM bin_inventories AS inventory
      JOIN duplicates
        ON duplicates.warehouse_bin_id = inventory.warehouse_bin_id AND duplicates.sku = inventory.sku
      WHERE reservation.bin_inventory_id = inventory.id AND inventory.id <> duplicates.keeper
    SQL

    execute <<~SQL
      WITH duplicates AS (#{DUPLICATES})
      UPDATE bin_inventories AS inventory
      SET quantity = duplicates.quantity,
          reserved_quantity = duplicates.reserved_quantity,
          created_at = duplicates.created_at,
          updated_at = now()
      FROM duplicates
      WHERE inventory.id = duplicates.keeper
    SQL

    execute <<~SQL
      WITH duplicates AS (#{DUPLICATES})
      DELETE FROM bin_inventories AS inventory
      USING duplicates
      WHERE inventory.warehouse_bin_id = duplicates.warehouse_bin_id
        AND inventory.sku = duplicates.sku
        AND inventory.id <> duplicates.keeper
    SQL
  end

  def refusal(contested)
    rows = contested.map do |group|
      "warehouse_bin_id=#{group['warehouse_bin_id']} sku=#{group['sku']} " \
        "bin_inventories.id=#{group['ids']} owners=#{group['owners']}"
    end

    "bin_inventories holds one sku in one bin on several rows with different owners, so merging them " \
      "would decide whose goods they are. Settle the owner of each row, then migrate again: #{rows.join('; ')}"
  end
end
