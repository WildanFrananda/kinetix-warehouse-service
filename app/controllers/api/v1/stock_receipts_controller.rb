# typed: strict

module Api
  module V1
    class StockReceiptsController < ApplicationController
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

        service = Inventory::ReceiveStockService.new(
          bin_code: params[:bin_code].to_s,
          sku: params[:sku].to_s,
          quantity: params[:quantity].to_i,
          idempotency_key: key,
          received_by_principal_id: api_claims.principal_id,
          note: params[:note]&.to_s
        )
        result = service.call

        case result.error
        when nil
          render json: {
            id: result.receipt&.id,
            sku: result.receipt&.sku,
            quantity: result.receipt&.quantity,
            bin_code: params[:bin_code].to_s,
            quantity_on_hand: result.quantity_on_hand,
            replayed: result.replayed
          }, status: result.replayed ? :ok : :created
        when Inventory::ReceiveStockService::BIN_NOT_FOUND
          render json: { error: "no bin with that code — create it before booking goods into it" },
                 status: :unprocessable_entity
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end
    end
  end
end
