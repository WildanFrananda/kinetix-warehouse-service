# typed: strict

module Api
  module V1
    class StockAdjustmentsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStaffAuthorization
      include ApiAdminAudit
      include ApiStringParams
      include ApiLedgerQuery

      STRING_FIELDS = T.let(%i[idempotency_key merchant_principal_id bin_code sku reason note].freeze, T::Array[Symbol])

      sig { void }
      def index
        return unless require_staff!

        page = ledger.adjustments(filter: stock_filter, before: query_id(:before), limit: page_limit)
        render(
          json: { adjustments: page.items.map { |row| adjustment_row(row) }, next_before_id: page.last_shown&.id }
        )
      end

      sig { void }
      def create
        return unless require_staff!

        action = Kinetix::Metrics::AdminActions::STOCK_ADJUST
        audit_admin_action(action, target_keys: %i[bin_code sku]) { adjust }
      end

      private

      sig { params(row: StockAdjustment).returns(T::Hash[Symbol, T.untyped]) }
      def adjustment_row(row)
        {
          id: row.id,
          bin_code: T.must(row.warehouse_bin).bin_code,
          sku: row.sku,
          merchant_principal_id: row.merchant_principal_id,
          quantity_delta: row.quantity_delta,
          quantity_before: row.quantity_before,
          quantity_after: row.quantity_after,
          reason: row.reason,
          note: row.note,
          adjusted_by_principal_id: row.adjusted_by_principal_id,
          created_at: row.created_at
        }
      end

      sig { void }
      def adjust
        return if refuse_unusable_strings(STRING_FIELDS, coded: true)

        key = string_param(:idempotency_key).to_s
        if key.empty?
          render(json: { error: "idempotency_key is required" }, status: :bad_request)
          return
        end

        owner = string_param(:merchant_principal_id).to_s
        if owner.empty?
          render(
            json: { error: "merchant_principal_id is required: adjusting stock adjusts somebody's goods" },
            status: :bad_request
          )
          return
        end

        service = Inventory::AdjustStockService.new(
          bin_code: string_param(:bin_code).to_s,
          sku: string_param(:sku).to_s,
          quantity_delta: Kinetix::IntegerParam.parse(params[:quantity_delta], signed: true),
          reason: string_param(:reason).to_s,
          idempotency_key: key,
          adjusted_by_principal_id: api_claims.principal_id,
          merchant_principal_id: owner,
          note: string_param(:note)
        )
        result = service.call

        render_result(result)
      end

      sig { params(result: Inventory::AdjustStockService::Result).void }
      def render_result(result)
        case result.error
        when nil
          render(
            json: {
              id: result.adjustment&.id,
              sku: result.adjustment&.sku,
              quantity_delta: result.adjustment&.quantity_delta,
              reason: result.adjustment&.reason,
              bin_code: result.bin_code,
              quantity_before: result.adjustment&.quantity_before,
              quantity_on_hand: result.quantity_on_hand,
              reserved_quantity: result.reserved_quantity,
              replayed: result.replayed
            },
            status: result.replayed ? :ok : :created
          )
        when Inventory::AdjustStockService::INVALID_DELTA
          render(
            json: {
              error: "INVALID_DELTA",
              message: "quantity_delta must be a whole number other than 0, " \
                       "from #{Kinetix::IntegerParam::MIN_INT32} to #{Kinetix::IntegerParam::MAX_INT32}, " \
                       "written in digits"
            },
            status: :unprocessable_content
          )
        when Inventory::AdjustStockService::INVALID_IDEMPOTENCY_KEY
          render(
            json: {
              error: "INVALID_IDEMPOTENCY_KEY",
              message: "idempotency_key must be at most #{StockOperation::MAX_KEY_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::AdjustStockService::INVALID_BIN_CODE
          render(
            json: {
              error: "INVALID_BIN_CODE",
              message: "bin_code must be at most #{WarehouseBin::MAX_CODE_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::AdjustStockService::INVALID_NOTE
          render(
            json: {
              error: "INVALID_NOTE",
              message: "note must be at most #{StockAdjustment::MAX_NOTE_LENGTH} characters"
            },
            status: :unprocessable_content
          )
        when Inventory::AdjustStockService::STOCK_LIMIT_EXCEEDED
          render(
            json: {
              error: "STOCK_LIMIT_EXCEEDED",
              message: "this adjustment would put more than #{BinInventory::MAX_QUANTITY} units of the sku " \
                       "in that bin, more than it can count"
            },
            status: :unprocessable_content
          )
        when Inventory::AdjustStockService::WOULD_CUT_RESERVED
          render(
            json: {
              error: "that would cut into stock already reserved for orders",
              quantity_on_hand: result.quantity_on_hand,
              reserved_quantity: result.reserved_quantity,
              max_reduction: result.quantity_on_hand - result.reserved_quantity
            },
            status: :conflict
          )
        when Inventory::AdjustStockService::INVALID_MERCHANT_PRINCIPAL
          render(json: { error: "merchant_principal_id must be a UUID" }, status: :bad_request)
        when Inventory::AdjustStockService::IDEMPOTENCY_KEY_CONFLICT
          render(
            json: {
              error: "IDEMPOTENCY_KEY_CONFLICT",
              message: "that idempotency_key already made a different adjustment for this merchant"
            },
            status: :conflict
          )
        when Inventory::AdjustStockService::WRONG_OWNER
          render(json: { error: "that stock belongs to a different merchant" }, status: :conflict)
        when Inventory::AdjustStockService::STOCK_HAS_NO_OWNER
          render(
            json: { error: "that stock predates ownership — book it in again naming the merchant first" },
            status: :conflict
          )
        when Inventory::AdjustStockService::BIN_NOT_FOUND
          render(json: { error: "no bin with that code" }, status: :unprocessable_content)
        when Inventory::AdjustStockService::STOCK_NOT_FOUND
          render(
            json: { error: "that sku is not on that shelf — nothing to adjust" },
            status: :unprocessable_content
          )
        when Inventory::AdjustStockService::UNKNOWN_REASON
          render(
            json: { error: "reason must be one of #{StockAdjustment::REASONS.join(', ')}" },
            status: :unprocessable_content
          )
        else
          render(json: { error: result.error }, status: :unprocessable_content)
        end
      end
    end
  end
end
