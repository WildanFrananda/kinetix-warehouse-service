# typed: false
# frozen_string_literal: true

require "rails_helper"
require "fulfillment/v1/fulfillment_services_pb"
require_relative "../../app/rpc/fulfillment_service_handler"
require_relative "../../app/rpc/bin_stock_service_handler"

RSpec.describe Rpc::FulfillmentServiceHandler do
  PRINCIPAL = "11111111-2222-3333-4444-555555555555"

  let(:merchant) do
    Merchant.find_or_create_by!(name: "Test gRPC Merchant") do |m|
      m.code = "GRPC_TEST"
      m.cutoff_hour = 14
      m.principal_id = PRINCIPAL
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
        merchant_principal_id: PRINCIPAL,
        order_number: "ORD-GRPC-99",
        shipping_address: Common::V1::Address.new(
          recipient_name: "Jane Doe",
          phone_number: "08123456789",
          street_address: "777 Cyber Park",
          city: "Jakarta",
          postal_code: "12345"
        ),
        total_amount: Common::V1::Money.new(currency: "IDR", amount_minor: 25_000_000),
        items: [
          Common::V1::OrderItem.new(
            sku: "TSHIRT-BLK-M",
            product_name: "Black Cotton Tee M",
            quantity: 2,
            unit_price: Common::V1::Money.new(currency: "IDR", amount_minor: 12_500_000),
            bin_location: "Rak B-02"
          )
        ]
      )

      res = handler.create_order(req, nil)

      expect(res.success).to be(true)
      expect(res.order_number).to eq("ORD-GRPC-99")
      expect(res.status).to eq(:ORDER_STATUS_RECEIVED)
      expect(res.merchant_principal_id).to eq(PRINCIPAL)

      created_order = Order.find(res.order_id.to_i)
      expect(created_order.buyer_name).to eq("Jane Doe")
      expect(created_order.order_items.count).to eq(1)
    end

    it "refuses a principal no merchant here is linked to" do
      merchant

      res = handler.create_order(
        Fulfillment::V1::CreateOrderRequest.new(
          merchant_principal_id: "aaaaaaaa-0000-0000-0000-000000000000",
          order_number: "ORD-FAIL"
        ), nil
      )

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("UNKNOWN_MERCHANT")
    end

    it "refuses a request carrying no principal at all" do
      merchant

      res = handler.create_order(Fulfillment::V1::CreateOrderRequest.new(order_number: "ORD-FAIL"), nil)

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("UNKNOWN_MERCHANT")
    end

    it "attributes the order to the merchant the principal names, not to the first row" do
      merchant
      other = Merchant.create!(
        name: "Somebody Else", code: "OTHER", cutoff_hour: 14,
        principal_id: "bbbbbbbb-0000-0000-0000-000000000000"
      )

      res = handler.create_order(
        Fulfillment::V1::CreateOrderRequest.new(
          merchant_principal_id: other.principal_id,
          order_number: "ORD-OTHER",
          items: [ Common::V1::OrderItem.new(
            sku: "X-1", product_name: "X", quantity: 1,
            unit_price: Common::V1::Money.new(currency: "IDR", amount_minor: 100_000)
          ) ]
        ), nil
      )

      expect(res.success).to be(true)
      expect(Order.find(res.order_id.to_i).merchant_id).to eq(other.id)
    end
  end

  describe "#check_bin_stock via gRPC" do
    it "returns stock information for a given SKU" do
      merchant
      req = Fulfillment::V1::CheckBinStockRequest.new(
        merchant_principal_id: PRINCIPAL,
        sku: "TSHIRT-BLK-M"
      )

      res = bin_handler.check_bin_stock(req, nil)

      expect(res.found).to be(false)
    end
  end
end
