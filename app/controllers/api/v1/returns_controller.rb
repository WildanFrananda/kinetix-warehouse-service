# typed: strict

module Api
  module V1
    class ReturnsController < ApplicationController
      extend T::Sig
      include ApiAuthentication
      include ApiErrorHandling

      sig { void }
      def create
        merchant = require_api_merchant!
        return if merchant.nil?

        task = find_task(merchant, params[:fulfillment_task_id].to_i)
        return if task.nil?

        reason = params[:reason].to_s
        if reason.strip.empty?
          render json: { error: "Reason cannot be blank" }, status: :unprocessable_entity
          return
        end

        relay = T.let(Container[:order_grpc_client], Order::ReturnRelay)
        result = relay.open_return(
          merchant_principal_id: T.must(merchant.principal_id),
          order_number: T.must(task.order_number),
          reason: reason
        )

        if result[:success]
          render json: {
            return_number: result[:return_number],
            fulfillment_task_id: task.id,
            already_open: result[:already_open]
          }, status: :created
        else
          render_order_refused(result[:error])
        end
      end

      sig { void }
      def received
        merchant = require_api_merchant!
        return if merchant.nil?

        lines = Array(params[:lines]).map do |line|
          { sku: line[:sku].to_s, quantity: line[:quantity].to_i }
        end

        if lines.empty?
          render json: { error: "Name at least one SKU that came back" }, status: :unprocessable_entity
          return
        end

        relay = T.let(Container[:order_grpc_client], Order::ReturnRelay)
        result = relay.return_goods_received(
          merchant_principal_id: T.must(merchant.principal_id),
          return_number: params[:return_number].to_s,
          lines: lines,
          bin_code: params[:bin_code].to_s,
          received_at: Time.current
        )

        if result[:accepted]
          render json: {
            return_number: params[:return_number].to_s,
            already_recorded: result[:already_recorded]
          }, status: :ok
        else
          render_order_refused(result[:error])
        end
      end

      private

      sig { params(merchant: Merchant, task_id: Integer).returns(T.nilable(FulfillmentTask)) }
      def find_task(merchant, task_id)
        repository = T.let(Container[:fulfillment_task_repository], FulfillmentTaskRepositoryInterface)
        task = repository.find_by_id(merchant_id: T.must(merchant.id), id: task_id)

        if task.nil?
          render json: { error: "Fulfillment task not found" }, status: :not_found
          return nil
        end

        task
      end

      sig { params(detail: T.nilable(String)).void }
      def render_order_refused(detail)
        render json: {
          error: "RETURN_NOT_RECORDED",
          message: detail || "order did not accept this return, so nothing was recorded"
        }, status: :bad_gateway
      end
    end
  end
end
