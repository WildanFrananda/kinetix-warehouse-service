# Hand-written shims for the generated gRPC stubs.
#
# `creds` was typed `Symbol` because the only value ever passed was
# `:this_channel_is_insecure`. Every client speaks mTLS now and passes a
# `GRPC::Core::ChannelCredentials`, which the real `Stub#initialize` has always accepted — the
# shim was narrower than the thing it describes, so widening it is a correction, not a
# concession.
# typed: true

module Google
  module Protobuf
    class DescriptorPool
      extend T::Sig
      sig { returns(DescriptorPool) }
      def self.generated_pool; end

      sig { params(name: String).returns(T.untyped) }
      def lookup(name); end
    end

    class RepeatedField
      include Enumerable
      extend T::Sig
      sig { params(args: T.untyped).void }
      def initialize(*args); end
    end
  end
end

module Common
  module V1
    class Money
      extend T::Sig
      sig { params(currency_code: String, units: Integer, nanos: Integer).void }
      def initialize(currency_code: "", units: 0, nanos: 0); end
      sig { returns(String) }
      def currency_code; end
      sig { returns(Integer) }
      def units; end
      sig { returns(Integer) }
      def nanos; end
    end

    class GeoPoint
      extend T::Sig
      sig { params(latitude: Float, longitude: Float).void }
      def initialize(latitude: 0.0, longitude: 0.0); end
      sig { returns(Float) }
      def latitude; end
      sig { returns(Float) }
      def longitude; end
    end

    class Address
      extend T::Sig
      sig do
        params(
          recipient_name: String,
          phone_number: String,
          street_address: String,
          city: String,
          postal_code: String,
          location: T.nilable(GeoPoint)
        ).void
      end
      def initialize(recipient_name: "", phone_number: "", street_address: "", city: "", postal_code: "", location: nil); end
      sig { returns(String) }
      def recipient_name; end
      sig { returns(String) }
      def phone_number; end
      sig { returns(String) }
      def street_address; end
      sig { returns(String) }
      def city; end
      sig { returns(String) }
      def postal_code; end
      sig { returns(T.nilable(GeoPoint)) }
      def location; end
    end

    class OrderItem
      extend T::Sig
      sig do
        params(
          sku: String,
          product_name: String,
          quantity: Integer,
          price: T.nilable(Money),
          bin_location: String
        ).void
      end
      def initialize(sku: "", product_name: "", quantity: 0, price: nil, bin_location: ""); end
      sig { returns(String) }
      def sku; end
      sig { returns(String) }
      def product_name; end
      sig { returns(Integer) }
      def quantity; end
      sig { returns(T.nilable(Money)) }
      def price; end
      sig { returns(String) }
      def bin_location; end
    end

    class ErrorDetail
      extend T::Sig
      sig { params(error_code: String, message: String, field_violations: T::Array[String]).void }
      def initialize(error_code: "", message: "", field_violations: []); end
      sig { returns(String) }
      def error_code; end
      sig { returns(String) }
      def message; end
    end

    module OrderStatus
      ORDER_STATUS_UNSPECIFIED = 0
      ORDER_STATUS_RECEIVED = 1
      ORDER_STATUS_PACKING = 2
      ORDER_STATUS_PACKED = 3
      ORDER_STATUS_DISPATCHED = 4
      ORDER_STATUS_IN_TRANSIT = 5
      ORDER_STATUS_DELIVERED = 6
      ORDER_STATUS_CANCELLED = 7
    end

    module CourierStatus
      COURIER_STATUS_UNSPECIFIED = 0
      COURIER_STATUS_IDLE = 1
      COURIER_STATUS_ASSIGNED = 2
      COURIER_STATUS_EN_ROUTE_PICKUP = 3
      COURIER_STATUS_PICKED_UP = 4
      COURIER_STATUS_EN_ROUTE_DELIVERY = 5
      COURIER_STATUS_COMPLETED = 6
    end

    module ReturnStatus
      RETURN_STATUS_UNSPECIFIED = 0
      RETURN_STATUS_REQUESTED = 1
      RETURN_STATUS_PICKED_UP_FROM_BUYER = 2
      RETURN_STATUS_RECEIVED_AT_WAREHOUSE = 3
      RETURN_STATUS_INSPECTED = 4
      RETURN_STATUS_RESOLVED = 5
      RETURN_STATUS_REJECTED = 6
    end
  end
end

module Fulfillment
  module V1
    class CreateOrderRequest
      extend T::Sig
      sig do
        params(
          merchant_api_key: String,
          order_number: String,
          shipping_address: T.nilable(Common::V1::Address),
          total_amount: T.nilable(Common::V1::Money),
          items: T::Array[Common::V1::OrderItem],
          buyer_name: String,
          buyer_phone: String
        ).void
      end
      def initialize(merchant_api_key: "", order_number: "", shipping_address: nil, total_amount: nil, items: [], buyer_name: "", buyer_phone: ""); end
      sig { returns(String) }
      def merchant_api_key; end
      sig { returns(String) }
      def order_number; end
      sig { returns(T.nilable(Common::V1::Address)) }
      def shipping_address; end
      sig { returns(T.nilable(Common::V1::Money)) }
      def total_amount; end
      sig { returns(T.untyped) }
      def items; end
      sig { returns(String) }
      def buyer_name; end
      sig { returns(String) }
      def buyer_phone; end
    end

    class CreateOrderResponse
      extend T::Sig
      sig do
        params(
          order_id: Integer,
          order_number: String,
          status: T.untyped,
          merchant_id: Integer,
          created_at: String,
          error: T.nilable(Common::V1::ErrorDetail)
        ).void
      end
      def initialize(order_id: 0, order_number: "", status: 0, merchant_id: 0, created_at: "", error: nil); end
      sig { returns(Integer) }
      def order_id; end
      sig { returns(String) }
      def order_number; end
      sig { returns(T.untyped) }
      def status; end
      sig { returns(Integer) }
      def merchant_id; end
      sig { returns(String) }
      def created_at; end
      sig { returns(T.nilable(Common::V1::ErrorDetail)) }
      def error; end
    end

    class GetOrderStatusRequest
      extend T::Sig
      sig { params(merchant_api_key: String, order_id: Integer, order_number: String).void }
      def initialize(merchant_api_key: "", order_id: 0, order_number: ""); end
      sig { returns(String) }
      def merchant_api_key; end
      sig { returns(Integer) }
      def order_id; end
      sig { returns(String) }
      def order_number; end
    end

    class GetOrderStatusResponse
      extend T::Sig
      sig do
        params(
          order_id: Integer,
          order_number: String,
          status: T.untyped,
          awb_number: String,
          pod_photo_url: String,
          driver_location: T.nilable(Common::V1::GeoPoint),
          updated_at: String
        ).void
      end
      def initialize(order_id: 0, order_number: "", status: 0, awb_number: "", pod_photo_url: "", driver_location: nil, updated_at: ""); end
    end

    class CancelOrderRequest
      extend T::Sig
      sig { params(merchant_api_key: String, order_id: Integer, reason: String).void }
      def initialize(merchant_api_key: "", order_id: 0, reason: ""); end
      sig { returns(String) }
      def merchant_api_key; end
      sig { returns(Integer) }
      def order_id; end
      sig { returns(String) }
      def reason; end
    end

    class CancelOrderResponse
      extend T::Sig
      sig { params(success: T::Boolean, message: String, current_status: T.untyped).void }
      def initialize(success: false, message: "", current_status: 0); end
    end

    class CheckBinStockRequest
      extend T::Sig
      sig { params(merchant_api_key: String, sku: String).void }
      def initialize(merchant_api_key: "", sku: ""); end
      sig { returns(String) }
      def merchant_api_key; end
      sig { returns(String) }
      def sku; end
    end

    class CheckBinStockResponse
      extend T::Sig
      sig do
        params(
          sku: String,
          product_name: String,
          physical_stock: Integer,
          allocated_stock: Integer,
          available_stock: Integer,
          bin_location: String,
          low_stock_warning: T::Boolean
        ).void
      end
      def initialize(sku: "", product_name: "", physical_stock: 0, allocated_stock: 0, available_stock: 0, bin_location: "", low_stock_warning: false); end
      sig { returns(String) }
      def sku; end
      sig { returns(Integer) }
      def available_stock; end
      sig { returns(String) }
      def bin_location; end
    end

    class ReserveStockRequest
      extend T::Sig
      sig { params(merchant_api_key: String, sku: String, quantity: Integer, order_number: String).void }
      def initialize(merchant_api_key: "", sku: "", quantity: 0, order_number: ""); end
      sig { returns(String) }
      def merchant_api_key; end
      sig { returns(String) }
      def sku; end
      sig { returns(Integer) }
      def quantity; end
      sig { returns(String) }
      def order_number; end
    end

    class ReserveStockResponse
      extend T::Sig
      sig do
        params(
          success: T::Boolean,
          bin_location: String,
          remaining_available: Integer,
          error: T.nilable(Common::V1::ErrorDetail)
        ).void
      end
      def initialize(success: false, bin_location: "", remaining_available: 0, error: nil); end
    end

    module FulfillmentService
      class Service; end
    end

    module BinStockService
      class Service; end
    end
  end
end

module Fleet
  module V1
    class DispatchCourierRequest
      extend T::Sig
      sig do
        params(
          merchant_api_key: String,
          order_id: Integer,
          order_number: String,
          pickup_address: T.nilable(Common::V1::Address),
          delivery_address: T.nilable(Common::V1::Address)
        ).void
      end
      def initialize(merchant_api_key: "", order_id: 0, order_number: "", pickup_address: nil, delivery_address: nil); end
    end

    class DispatchCourierResponse
      extend T::Sig
      sig { returns(T::Boolean) }
      def success; end
      sig { returns(String) }
      def dispatch_ref; end
      sig { returns(String) }
      def assigned_driver_name; end
      sig { returns(String) }
      def assigned_driver_phone; end
      sig { returns(String) }
      def vehicle; end
      sig { returns(Integer) }
      def eta_minutes; end
    end

    class DriverLocationPing; end
    class DriverLocationAck; end

    module CourierTelemetryService
      class Service; end
      class Stub
        extend T::Sig
        sig { params(host: String, creds: T.any(Symbol, GRPC::Core::ChannelCredentials), timeout: Integer).void }
        def initialize(host, creds, timeout: 5); end
        sig { params(req: DispatchCourierRequest).returns(DispatchCourierResponse) }
        def dispatch_courier(req); end
      end
    end
  end
end

module Returns
  module V1
    class SubmitReturnClaimRequest; end
    class SubmitReturnClaimResponse; end
    class GetReturnStatusRequest; end
    class GetReturnStatusResponse; end

    module ReturnService
      class Service; end
    end
  end
end
