# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_services_pb"

module Rpc
  class FulfillmentServiceHandler < Fulfillment::V1::FulfillmentService::Service
    extend T::Sig

    sig { void }
    def initialize
      super
    end

    MINOR_UNITS_PER_MAJOR = T.let(BigDecimal("100"), BigDecimal)

    sig do
      params(
        req: Fulfillment::V1::CreateOrderRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::CreateOrderResponse)
    end
    def create_order(req, _call)
      merchant = merchant_for(req.merchant_principal_id)

      unless merchant
        return Fulfillment::V1::CreateOrderResponse.new(
          success: false,
          error: Common::V1::ErrorDetail.new(
            error_code: "UNKNOWN_MERCHANT",
            message: "no merchant in this warehouse is linked to that principal"
          )
        )
      end

      total_calculated = BigDecimal("0")
      raw_items = req.items.map do |item|
        item_price = if item.unit_price
          BigDecimal(item.unit_price.amount_minor.to_s) / MINOR_UNITS_PER_MAJOR
        else
          BigDecimal("0")
        end
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

      usecase = T.let(Container[:create_order_service], Orders::CreateOrderService)
      res = usecase.call(merchant_id: merchant.id, form: form)

      if res.success? && res.data
        data = T.cast(res.data, Orders::CreateOrderService::ResultData)
        pb_status = map_order_status(data.status)

        Fulfillment::V1::CreateOrderResponse.new(
          success: true,
          order_id: data.id.to_s,
          order_number: data.order_number,
          status: pb_status,
          merchant_principal_id: req.merchant_principal_id,
          created_at: Google::Protobuf::Timestamp.new(seconds: Time.current.to_i)
        )
      else
        Fulfillment::V1::CreateOrderResponse.new(
          success: false,
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
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::GetOrderStatusResponse)
    end
    def get_order_status(req, _call)
      merchant = merchant_for(req.merchant_principal_id)

      unless merchant
        return Fulfillment::V1::GetOrderStatusResponse.new(found: false)
      end

      order_repo = T.let(Container[:order_repository], OrderRepositoryInterface)
      numeric_id = req.order_id.to_i
      ord = if numeric_id.positive?
        order_repo.find_by_id(merchant_id: merchant.id, id: numeric_id)
      elsif req.order_number.present?
        order_repo.find_by_order_number(merchant_id: merchant.id, order_number: req.order_number)
      end

      unless ord && ord.merchant_id == merchant.id
        return Fulfillment::V1::GetOrderStatusResponse.new(found: false)
      end

      Fulfillment::V1::GetOrderStatusResponse.new(
        found: true,
        order_id: ord.id.to_s,
        order_number: ord.order_number || "",
        status: map_order_status(ord.status || ""),
        updated_at: Google::Protobuf::Timestamp.new(seconds: ord.updated_at.to_i)
      )
    end

    sig do
      params(
        req: Fulfillment::V1::CancelOrderRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::CancelOrderResponse)
    end
    def cancel_order(req, _call)
      merchant = merchant_for(req.merchant_principal_id)

      unless merchant
        return Fulfillment::V1::CancelOrderResponse.new(
          success: false,
          message: "no merchant in this warehouse is linked to that principal"
        )
      end

      order_repo = T.let(Container[:order_repository], OrderRepositoryInterface)
      ord = order_repo.find_by_id(merchant_id: merchant.id, id: req.order_id.to_i)

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

    sig { params(principal_id: String).returns(T.nilable(Merchant)) }
    def merchant_for(principal_id)
      return nil if principal_id.empty?

      Merchant.find_by(principal_id: principal_id)
    end

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
