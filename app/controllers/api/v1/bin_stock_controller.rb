# typed: strict

module Api
  module V1
    class BinStockController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStaffAuthorization
      include ApiLedgerQuery

      sig { void }
      def index
        return unless require_staff!

        page = ledger.stock(filter: stock_filter, after: query_id(:after), limit: page_limit)
        render(json: { stock: page.items.map { |row| stock_row(row) }, next_after_id: page.last_shown&.id })
      end

      private

      sig { params(row: BinInventory).returns(T::Hash[Symbol, T.untyped]) }
      def stock_row(row)
        bin = T.must(row.warehouse_bin)

        {
          id: row.id,
          bin_code: bin.bin_code,
          zone: bin.zone,
          shelf_level: bin.shelf_level,
          sku: row.sku,
          merchant_principal_id: row.merchant_principal_id,
          quantity: row.quantity,
          reserved_quantity: row.reserved_quantity,
          available_quantity: row.available_quantity,
          updated_at: row.updated_at
        }
      end
    end
  end
end
