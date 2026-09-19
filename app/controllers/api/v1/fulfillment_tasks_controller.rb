# typed: strict

module Api
  module V1
    class FulfillmentTasksController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling

      sig { void }
      def queue
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:task_queue_service], Fulfillment::TaskQueueService)
        result = service.call(merchant_id: merchant.id)

        render_result(result)
      end

      sig { void }
      def update_status
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:advance_task_service], Fulfillment::AdvanceTaskService)
        result = service.call(
          merchant_id: merchant.id,
          task_id: params[:id].to_i,
          new_status: params[:status].to_s
        )

        render_result(result)
      end

      sig { void }
      def generate_label
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
        result = service.call(merchant_id: merchant.id, fulfillment_task_id: params[:id].to_i)

        render_result(result)
      end

      private

      sig { params(result: BaseService::Result).void }
      def render_result(result)
        if result.success?
          render json: result.data
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end
    end
  end
end
