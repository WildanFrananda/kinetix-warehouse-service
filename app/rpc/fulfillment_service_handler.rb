# typed: strict
# frozen_string_literal: true

require_relative "../../lib/generated/fulfillment/v1/fulfillment_service_services_pb"

module Rpc
  class FulfillmentServiceHandler < Fulfillment::V1::FulfillmentService::Service
    extend T::Sig

    sig { void }
    def initialize
      super
    end

    sig do
      params(
        req: Fulfillment::V1::CreateOrderRequest,
        _call: T.nilable(GRPC::ActiveCall)
      ).returns(Fulfillment::V1::CreateOrderResponse)
    end
    def create_order(req, _call)
      merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
      merchant = merchant_repo.find_by_api_key(req.merchant_api_key)

      unless merchant
        return Fulfillment::V1::CreateOrderResponse.new(
          error: Common::V1::ErrorDetail.new(
            error_code: "UNAUTHORIZED",
            message: "Invalid merchant_api_key"
          )
        )
      end

      raw_items = req.items.map do |item|
        item_price = item.price ? BigDecimal(item.price.units.to_s) : BigDecimal("0")
        Orders::CreateOrderForm::ItemInput.new(
          sku: item.sku,
          product_name: item.product_name,
          quantity: item.quantity,
          price: item_price
        )
      end

      addr = req.shipping_address
      shipping_str = addr ? "#{addr.street_address}, #{addr.city} #{addr.postal_code}".strip : "Main Street"
      buyer_phone = addr ? addr.phone_number : ""

      tot_amt_obj = req.total_amount
      total_amt = if tot_amt_obj
        BigDecimal(tot_amt_obj.units.to_s)
      else
        BigDecimal("0")
      end

      form = Orders::CreateOrderForm.new(
        order_number: req.order_number.presence || "ORD-#{SecureRandom.hex(4).upcase}",
        buyer_name: addr ? addr.recipient_name : "Customer",
        buyer_phone: buyer_phone,
        shipping_address: shipping_str,
        total_amount: total_amt,
        items: raw_items
      )

      service = T.let(Container[:create_order_service], Orders::CreateOrderService)
      result = service.call(
        merchant_id: merchant.id,
        form: form
      )

      if result.success?
        ord_data = T.cast(result.data, Orders::CreateOrderService::ResultData)

        Fulfillment::V1::CreateOrderResponse.new(
          order_id: ord_data.id,
          order_number: ord_data.order_number,
          status: Common::V1::OrderStatus::ORDER_STATUS_RECEIVED,
          merchant_id: merchant.id,
          created_at: Time.current.iso8601
        )
      else
        Fulfillment::V1::CreateOrderResponse.new(
          error: Common::V1::ErrorDetail.new(
            error_code: "CREATE_ORDER_FAILED",
            message: result.error || "Failed to create order"
          )
        )
      end
    end

    sig do
      params(
        req: Fulfillment::V1::GetOrderStatusRequest,
        _call: T.nilable(GRPC::ActiveCall)
      ).returns(Fulfillment::V1::GetOrderStatusResponse)
    end
    def get_order_status(req, _call)
      merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
      merchant = merchant_repo.find_by_api_key(req.merchant_api_key)

      unless merchant
        return Fulfillment::V1::GetOrderStatusResponse.new
      end

      order_repo = T.let(Container[:order_repository], OrderRepositoryInterface)
      ord = if req.order_id.positive?
        order_repo.find_by_id(merchant_id: merchant.id, id: req.order_id)
      elsif req.order_number.present?
        order_repo.find_by_order_number(merchant_id: merchant.id, order_number: req.order_number)
      end

      unless ord && ord.merchant_id == merchant.id
        return Fulfillment::V1::GetOrderStatusResponse.new
      end

      pb_status = map_order_status(ord.status || "")
      updated_str = ord.updated_at.iso8601

      Fulfillment::V1::GetOrderStatusResponse.new(
        order_id: ord.id,
        order_number: ord.order_number || "",
        status: pb_status,
        updated_at: updated_str
      )
    end

    sig do
      params(
        req: Fulfillment::V1::CancelOrderRequest,
        _call: T.nilable(GRPC::ActiveCall)
      ).returns(Fulfillment::V1::CancelOrderResponse)
    end
    def cancel_order(req, _call)
      merchant_repo = T.let(Container[:merchant_repository], MerchantRepositoryInterface)
      merchant = merchant_repo.find_by_api_key(req.merchant_api_key)

      unless merchant
        return Fulfillment::V1::CancelOrderResponse.new(
          success: false,
          message: "Invalid merchant_api_key"
        )
      end

      order_repo = T.let(Container[:order_repository], OrderRepositoryInterface)
      ord = order_repo.find_by_id(merchant_id: merchant.id, id: req.order_id)

      unless ord && ord.merchant_id == merchant.id
        return Fulfillment::V1::CancelOrderResponse.new(
          success: false,
          message: "Order not found"
        )
      end

      if [ "dispatched", "in_transit", "delivered" ].include?(ord.status)
        return Fulfillment::V1::CancelOrderResponse.new(
          success: false,
          message: "Cannot cancel order in status: #{ord.status}",
          current_status: map_order_status(ord.status || "")
        )
      end

      ord.update!(status: "cancelled")
      Fulfillment::V1::CancelOrderResponse.new(
        success: true,
        message: "Order cancelled successfully",
        current_status: Common::V1::OrderStatus::ORDER_STATUS_CANCELLED
      )
    end

    private

    sig { params(status: String).returns(Integer) }
    def map_order_status(status)
      case status
      when "received" then Common::V1::OrderStatus::ORDER_STATUS_RECEIVED
      when "packing" then Common::V1::OrderStatus::ORDER_STATUS_PACKING
      when "packed" then Common::V1::OrderStatus::ORDER_STATUS_PACKED
      when "dispatched" then Common::V1::OrderStatus::ORDER_STATUS_DISPATCHED
      when "in_transit" then Common::V1::OrderStatus::ORDER_STATUS_IN_TRANSIT
      when "delivered" then Common::V1::OrderStatus::ORDER_STATUS_DELIVERED
      when "cancelled" then Common::V1::OrderStatus::ORDER_STATUS_CANCELLED
      else Common::V1::OrderStatus::ORDER_STATUS_UNSPECIFIED
      end
    end
  end
end
