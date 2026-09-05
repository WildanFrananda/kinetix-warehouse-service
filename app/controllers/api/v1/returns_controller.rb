# typed: strict

module Api
  module V1
    class ReturnsController < ApplicationController
      extend T::Sig
      include ApiAuthentication

      sig { void }
      def create
        merchant = require_api_merchant!
        return if merchant.nil?

        form = Returns::InitiateReturnForm.new(
          order_id: params[:order_id].to_i,
          reason: params[:reason].to_s
        )

        service = T.let(Container[:initiate_return_service], Returns::InitiateReturnService)
        result = service.call(merchant_id: merchant.id, form: form)

        if result.success?
          render json: result.data, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      sig { void }
      def update_status
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:update_return_status_service], Returns::UpdateReturnStatusService)
        result = service.call(
          merchant_id: merchant.id,
          return_id: params[:id].to_i,
          new_status: params[:status].to_s
        )


        if result.success?
          render json: result.data
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end
    end
  end
end
