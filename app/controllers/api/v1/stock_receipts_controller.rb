# typed: strict

module Api
  module V1
    class StockReceiptsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStaffAuthorization
      include ApiAdminAudit
      include ApiStringParams
      include ApiLedgerQuery

      STRING_FIELDS = T.let(%i[idempotency_key merchant_principal_id bin_code sku note].freeze, T::Array[Symbol])

      sig { void }
      def index
        return unless require_staff!

        page = ledger.receipts(filter: stock_filter, before: query_id(:before), limit: page_limit)
        render(json: { receipts: page.items.map { |row| receipt_row(row) }, next_before_id: page.last_shown&.id })
      end

      sig { void }
      def create
        return unless require_staff!

        action = Kinetix::Metrics::AdminActions::STOCK_RECEIVE
        audit_admin_action(action, target_keys: %i[bin_code sku]) { receive }
      end

      private

      sig { params(row: StockReceipt).returns(T::Hash[Symbol, T.untyped]) }
      def receipt_row(row)
        {
          id: row.id,
          bin_code: T.must(row.warehouse_bin).bin_code,
          sku: row.sku,
          merchant_principal_id: row.merchant_principal_id,
          quantity: row.quantity,
          note: row.note,
          received_by_principal_id: row.received_by_principal_id,
          created_at: row.created_at
        }
      end

      sig { void }
      def receive
        return if refuse_unusable_strings(STRING_FIELDS, coded: true)

        key = string_param(:idempotency_key).to_s
        if key.empty?
          render(json: { error: "idempotency_key is required" }, status: :bad_request)
          return
        end

        owner = string_param(:merchant_principal_id).to_s
        if owner.empty?
          render(
            json: { error: "merchant_principal_id is required: goods on a shelf belong to somebody" },
            status: :bad_request
          )
          return
        end

        service = Inventory::ReceiveStockService.new(
          bin_code: string_param(:bin_code).to_s,
          sku: string_param(:sku).to_s,
          quantity: Kinetix::IntegerParam.parse(params[:quantity], signed: false),
          idempotency_key: key,
          received_by_principal_id: api_claims.principal_id,
          merchant_principal_id: owner,
          note: string_param(:note)
        )
        result = service.call

        render_result(result)
      end

      sig { params(result: Inventory::ReceiveStockService::Result).void }
      def render_result(result)
        case result.error
        when nil
          render(
            json: {
              id: result.receipt&.id,
              sku: result.receipt&.sku,
              quantity: result.receipt&.quantity,
              bin_code: result.bin_code,
              quantity_on_hand: result.quantity_on_hand,
              replayed: result.replayed
            },
            status: result.replayed ? :ok : :created
          )
        when Inventory::ReceiveStockService::INVALID_QUANTITY
          render(
            json: {
              error: "INVALID_QUANTITY",
              message: "quantity must be a whole number from 1 to #{BinInventory::MAX_QUANTITY}, " \
                       "written in digits"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::INVALID_IDEMPOTENCY_KEY
          render(
            json: {
              error: "INVALID_IDEMPOTENCY_KEY",
              message: "idempotency_key must be at most #{StockOperation::MAX_KEY_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::INVALID_BIN_CODE
          render(
            json: {
              error: "INVALID_BIN_CODE",
              message: "bin_code must be at most #{WarehouseBin::MAX_CODE_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::INVALID_NOTE
          render(
            json: {
              error: "INVALID_NOTE",
              message: "note must be at most #{StockReceipt::MAX_NOTE_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::STOCK_LIMIT_EXCEEDED
          render(
            json: {
              error: "STOCK_LIMIT_EXCEEDED",
              message: "this receipt would put more than #{BinInventory::MAX_QUANTITY} units of the sku " \
                       "in that bin, more than it can count; book the rest into another bin"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::INVALID_MERCHANT_PRINCIPAL
          render(json: { error: "merchant_principal_id must be a UUID" }, status: :bad_request)
        when Inventory::ReceiveStockService::INVALID_SKU
          render(
            json: {
              error: "sku is required and must be at most #{StockOperation::MAX_SKU_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::UNKNOWN_MERCHANT
          render(
            json: {
              error: "UNKNOWN_MERCHANT",
              message: "identity knows no merchant with that principal, so no goods can be booked for it"
            },
            status: :unprocessable_content
          )
        when Inventory::ReceiveStockService::IDEMPOTENCY_KEY_CONFLICT
          render(
            json: {
              error: "IDEMPOTENCY_KEY_CONFLICT",
              message: "that idempotency_key already booked a different receipt for this merchant"
            },
            status: :conflict
          )
        when Inventory::ReceiveStockService::WRONG_OWNER
          render(
            json: { error: "that sku is already on this shelf under a different merchant" },
            status: :conflict
          )
        when Inventory::ReceiveStockService::BIN_NOT_FOUND
          render(
            json: { error: "no bin with that code — create it before booking goods into it" },
            status: :unprocessable_content
          )
        else
          render(json: { error: result.error }, status: :unprocessable_content)
        end
      end
    end
  end
end
