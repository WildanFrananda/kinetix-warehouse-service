# typed: strict

module Api
  module V1
    class OrdersController < ApplicationController
      extend T::Sig
      include ApiAuthentication

      sig { void }
      def create
        merchant = require_api_merchant!
        return if merchant.nil?


        raw_items = params[:items]
        items = T.let([], T::Array[Orders::CreateOrderForm::ItemInput])
        if raw_items.is_a?(Array)
          raw_items.each do |item|
            next unless item.is_a?(ActionController::Parameters) || item.is_a?(Hash)

            items << Orders::CreateOrderForm::ItemInput.new(
              sku: item[:sku].to_s,
              product_name: item[:product_name].to_s,
              quantity: item[:quantity].to_i,
              price: BigDecimal(item[:price].to_s)
            )
          end
        end

        form = Orders::CreateOrderForm.new(
          buyer_name: params[:buyer_name].to_s,
          buyer_phone: params[:buyer_phone].to_s,
          shipping_address: params[:shipping_address].to_s,
          order_number: params[:order_number].to_s,
          total_amount: BigDecimal(params[:total_amount].to_s),
          items: items
        )


        return render json: { errors: form.errors }, status: :unprocessable_entity unless form.valid?

        service = T.let(Container[:create_order_service], Orders::CreateOrderService)
        result = service.call(
          merchant_id: merchant.id,
          form: form
        )

        if result.success?
          render json: result.data, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      sig { void }
      def queue
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:get_order_queue_service], Orders::GetOrderQueueService)
        result = service.call(merchant_id: merchant.id)

        if result.success?
          render json: result.data
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      sig { void }
      def update_status
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:update_order_status_service], Orders::UpdateOrderStatusService)
        result = service.call(
          merchant_id: merchant.id,
          order_id: params[:id].to_i,
          new_status: params[:status].to_s
        )

        if result.success?
          render json: result.data
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      sig { void }
      def generate_label
        merchant = require_api_merchant!
        return if merchant.nil?

        service = T.let(Container[:generate_shipping_label_service], Labels::GenerateShippingLabelService)
        result = service.call(
          merchant_id: merchant.id,

          order_id: params[:id].to_i
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
