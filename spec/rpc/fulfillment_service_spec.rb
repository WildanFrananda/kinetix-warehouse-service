# typed: false
# frozen_string_literal: true

require "rails_helper"
require_relative "../../lib/generated/fulfillment/v1/fulfillment_service_services_pb"
require_relative "../../lib/generated/fulfillment/v1/bin_stock_service_services_pb"
require_relative "../../app/rpc/fulfillment_service_handler"
require_relative "../../app/rpc/bin_stock_service_handler"

RSpec.describe Rpc::FulfillmentServiceHandler do
  let(:merchant) do
    Merchant.find_or_create_by!(name: "Test gRPC Merchant") do |m|
      m.code = "GRPC_TEST"
      m.cutoff_hour = 14
    end
  end

  let(:handler) { Rpc::FulfillmentServiceHandler.new }
  let(:bin_handler) { Rpc::BinStockServiceHandler.new }

  describe "#create_order via gRPC" do
    around do |example|
      travel_to(Time.zone.local(2026, 1, 15, 9, 0, 0)) { example.run }
    end

    it "creates an order successfully with Protobuf parameters" do
      merchant
      req = Fulfillment::V1::CreateOrderRequest.new(
        merchant_api_key: "",
        order_number: "ORD-GRPC-99",
        shipping_address: Common::V1::Address.new(
          recipient_name: "Jane Doe",
          phone_number: "08123456789",
          street_address: "777 Cyber Park",
          city: "Jakarta",
          postal_code: "12345"
        ),
        total_amount: Common::V1::Money.new(currency_code: "IDR", units: 250000, nanos: 0),
        items: [
          Common::V1::OrderItem.new(
            sku: "TSHIRT-BLK-M",
            product_name: "Black Cotton Tee M",
            quantity: 2,
            price: Common::V1::Money.new(currency_code: "IDR", units: 125000, nanos: 0),
            bin_location: "Rak B-02"
          )
        ]
      )

      res = handler.create_order(req, nil)

      expect(res.order_id).to be > 0
      expect(res.order_number).to eq("ORD-GRPC-99")
      expect(res.status).to eq(:ORDER_STATUS_RECEIVED)
      expect(res.merchant_id).to eq(merchant.id)

      created_order = Order.find(res.order_id)
      expect(created_order.buyer_name).to eq("Jane Doe")
      expect(created_order.order_items.count).to eq(1)
    end

    it "refuses the call when the warehouse holds no merchant to attribute it to" do
      expect(Merchant.count).to eq(0)

      res = handler.create_order(
        Fulfillment::V1::CreateOrderRequest.new(order_number: "ORD-FAIL"), nil
      )

      expect(res.error.error_code).to eq("UNAUTHORIZED")
    end

    # Characterisation, not an endorsement. `merchant_api_key` is a frozen wire field that no
    # handler reads: the transport is guarded by mTLS and the SPIFFE peer interceptor, and the
    # handler attributes every call to `Merchant.first`. So an arbitrary value in this field
    # creates a real order under whichever merchant happens to be first.
    #
    # This test exists to fail the moment that changes. S9 replaces the field with a principal
    # id and makes tenancy explicit; when it does, this expectation flips and the spec must be
    # rewritten to assert the refusal rather than the acceptance.
    it "ignores merchant_api_key entirely — tenancy comes from Merchant.first (S9 will change this)" do
      merchant
      res = handler.create_order(
        Fulfillment::V1::CreateOrderRequest.new(
          merchant_api_key: "INVALID_KEY",
          order_number: "ORD-UNCHECKED",
          shipping_address: Common::V1::Address.new(
            recipient_name: "Mallory",
            phone_number: "08000000000",
            street_address: "1 Nowhere",
            city: "Jakarta",
            postal_code: "10000"
          ),
          total_amount: Common::V1::Money.new(currency_code: "IDR", units: 1000, nanos: 0),
          items: [
            Common::V1::OrderItem.new(
              sku: "X-1",
              product_name: "X",
              quantity: 1,
              price: Common::V1::Money.new(currency_code: "IDR", units: 1000, nanos: 0)
            )
          ]
        ), nil
      )

      expect(res.error).to be_nil
      expect(res.order_id).to be > 0
      expect(res.merchant_id).to eq(merchant.id)
    end
  end

  describe "#check_bin_stock via gRPC" do
    it "returns stock information for a given SKU" do
      merchant
      req = Fulfillment::V1::CheckBinStockRequest.new(
        merchant_api_key: "",
        sku: "TSHIRT-BLK-M"
      )

      res = bin_handler.check_bin_stock(req, nil)
      expect(res.sku).to eq("TSHIRT-BLK-M")
      expect(res.available_stock).to be >= 0
    end
  end
end
