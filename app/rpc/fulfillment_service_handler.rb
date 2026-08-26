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
      merchant = Merchant.first

      unless merchant
        return Fulfillment::V1::CreateOrderResponse.new(
          error: Common::V1::ErrorDetail.new(
            error_code: "UNAUTHORIZED",
            message: "No active merchant found in warehouse database"
          )
        )
      end

      total_calculated = BigDecimal("0")
      raw_items = req.items.map do |item|
        item_price = item.price ? BigDecimal(item.price.units.to_s) : BigDecimal("0")
        total_calculated += item_price * BigDecimal(item.quantity.to_s)
        Orders::CreateOrderForm::ItemInput.new(
          sku: item.sku,
          product_name: item.product_name,
          quantity: item.quantity,
          price: item_price
        )
      end

      addr = req.shipping_address
      recipient_name = addr ? addr.recipient_name : "Customer"
      phone_number = addr ? addr.phone_number : "08123456789"
      street_address = addr ? addr.street_address : "Main Street 123"

      form = Orders::CreateOrderForm.new(
        order_number: req.order_number.empty? ? "ORD-#{SecureRandom.hex(4).upcase}" : req.order_number,
        buyer_name: recipient_name,
        buyer_phone: phone_number,
        shipping_address: street_address,
        total_amount: total_calculated,
        items: raw_items
      )

      usecase = T.let(Container[:create_order_usecase], Orders::CreateOrderService)
      res = usecase.call(merchant_id: merchant.id, form: form)

      if res.success? && res.data
        data = T.cast(res.data, Orders::CreateOrderService::ResultData)
        pb_status = map_order_status(data.status)

        Fulfillment::V1::CreateOrderResponse.new(
          order_id: data.id,
          order_number: data.order_number,
          status: pb_status,
          merchant_id: merchant.id,
          created_at: Time.current.iso8601
        )
      else
        Fulfillment::V1::CreateOrderResponse.new(
          error: Common::V1::ErrorDetail.new(
            error_code: "VALIDATION_FAILED",
            message: res.error || "Order creation failed"
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
      merchant = Merchant.first

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
      merchant = Merchant.first

      unless merchant
        return Fulfillment::V1::CancelOrderResponse.new(
          success: false,
          message: "No active merchant found"
        )
      end

      order_repo = T.let(Container[:order_repository], OrderRepositoryInterface)
      ord = order_repo.find_by_id(merchant_id: merchant.id, id: req.order_id)

      unless ord
        return Fulfillment::V1::CancelOrderResponse.new(
          success: false,
          message: "Order ##{req.order_id} not found"
        )
      end

      ord.update!(status: "cancelled")

      Fulfillment::V1::CancelOrderResponse.new(
        success: true,
        message: "Order ##{req.order_id} has been cancelled",
        current_status: Common::V1::OrderStatus::ORDER_STATUS_CANCELLED
      )
    end

    private

    sig { params(status_str: String).returns(Integer) }
    def map_order_status(status_str)
      case status_str.downcase
      when "received", "pending"
        Common::V1::OrderStatus::ORDER_STATUS_RECEIVED
      when "packing"
        Common::V1::OrderStatus::ORDER_STATUS_PACKING
      when "packed"
        Common::V1::OrderStatus::ORDER_STATUS_PACKED
      when "dispatched"
        Common::V1::OrderStatus::ORDER_STATUS_DISPATCHED
      when "in_transit"
        Common::V1::OrderStatus::ORDER_STATUS_IN_TRANSIT
      when "delivered"
        Common::V1::OrderStatus::ORDER_STATUS_DELIVERED
      when "cancelled"
        Common::V1::OrderStatus::ORDER_STATUS_CANCELLED
      else
        Common::V1::OrderStatus::ORDER_STATUS_UNSPECIFIED
      end
    end
  end
end
