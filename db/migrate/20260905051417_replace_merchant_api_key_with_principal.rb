# typed: strict
# frozen_string_literal: true

class ReplaceMerchantApiKeyWithPrincipal < ActiveRecord::Migration[8.1]
  def up
    add_column :merchants, :principal_id, :uuid, null: true
    add_index :merchants, :principal_id, unique: true

    remove_index :merchants, :api_key if index_exists?(:merchants, :api_key)
    remove_column :merchants, :api_key
  end

  def down
    add_column :merchants, :api_key, :string
    change_column_null :merchants, :api_key, false, "REVOKED-#{SecureRandom.hex(8)}"
    remove_index :merchants, :principal_id
    remove_column :merchants, :principal_id
  end
end
