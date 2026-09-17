# typed: strict

module Api
  module V1
    class StockAdjustmentsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling
      include ApiStaffAuthorization

      sig { void }
      def create
        return unless require_staff!

        key = params[:idempotency_key].to_s
        if key.empty?
          render json: { error: "idempotency_key is required" }, status: :bad_request
          return
        end

        owner = params[:merchant_principal_id].to_s
        if owner.empty?
          render json: { error: "merchant_principal_id is required: adjusting stock adjusts somebody's goods" },
                 status: :bad_request
          return
        end

        service = Inventory::AdjustStockService.new(
          bin_code: params[:bin_code].to_s,
          sku: params[:sku].to_s,
          quantity_delta: params[:quantity_delta].to_i,
          reason: params[:reason].to_s,
          idempotency_key: key,
          adjusted_by_principal_id: api_claims.principal_id,
          merchant_principal_id: owner,
          note: params[:note]&.to_s
        )
        result = service.call

        case result.error
        when nil
          render json: {
            id: result.adjustment&.id,
            sku: result.adjustment&.sku,
            quantity_delta: result.adjustment&.quantity_delta,
            reason: result.adjustment&.reason,
            bin_code: params[:bin_code].to_s,
            quantity_before: result.adjustment&.quantity_before,
            quantity_on_hand: result.quantity_on_hand,
            reserved_quantity: result.reserved_quantity,
            replayed: result.replayed
          }, status: result.replayed ? :ok : :created
        when Inventory::AdjustStockService::WOULD_CUT_RESERVED
          writable = result.quantity_on_hand - result.reserved_quantity
          render json: {
            error: "that would cut into stock already reserved for orders",
            quantity_on_hand: result.quantity_on_hand,
            reserved_quantity: result.reserved_quantity,
            max_reduction: writable
          }, status: :conflict
        when Inventory::AdjustStockService::WRONG_OWNER
          render json: { error: "that stock belongs to a different merchant" }, status: :conflict
        when Inventory::AdjustStockService::STOCK_HAS_NO_OWNER
          render json: {
            error: "that stock predates ownership — book it in again naming the merchant first"
          }, status: :conflict
        when Inventory::AdjustStockService::BIN_NOT_FOUND
          render json: { error: "no bin with that code" }, status: :unprocessable_entity
        when Inventory::AdjustStockService::STOCK_NOT_FOUND
          render json: { error: "that sku is not on that shelf — nothing to adjust" },
                 status: :unprocessable_entity
        when Inventory::AdjustStockService::UNKNOWN_REASON
          render json: {
            error: "reason must be one of #{StockAdjustment::REASONS.join(', ')}"
          }, status: :unprocessable_entity
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end
    end
  end
end
