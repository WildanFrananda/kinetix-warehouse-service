# typed: strict
# frozen_string_literal: true

class ProjectMerchantsThatOwnStock < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO merchants (principal_id, created_at, updated_at)
      SELECT DISTINCT stocked.merchant_principal_id, now(), now()
      FROM bin_inventories AS stocked
      WHERE stocked.merchant_principal_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM merchants AS known WHERE known.principal_id = stocked.merchant_principal_id
        )
    SQL
  end

  def down; end
end
