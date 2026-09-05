# spec/services/orders/verify_scan_barcode_service_spec.rb
require "rails_helper"

RSpec.describe Orders::VerifyScanBarcodeService, type: :service do
  let!(:merchant) { Merchant.create!(code: "BH-001", name: "Boutique Hijab Premium", cutoff_hour: 14) }
  let!(:order) do
    Order.create!(
      merchant: merchant,
      order_number: "ORD-BH-1001",
      buyer_name: "Sarah Jane",
      buyer_phone: "081234567890",
      shipping_address: "124 Maple St",
      status: "received",
      total_amount: 350000.0,
      same_day_cutoff_at: Time.current + 2.hours
    )
  end

  let!(:order_item) do
    order.order_items.create!(
      sku: "BH-SLK-NVY",
      product_name: "Premium Silk Hijab (Navy)",
      quantity: 1,
      price: 350000.0,
      bin_location: "Rak A-01, Bin 12"
    )
  end

  let(:service) { Container[:verify_scan_barcode_service] }

  describe "#call" do
    context "when scanned code matches SKU" do
      it "verifies barcode, updates order status, and returns success result" do
        result = service.call(merchant_id: merchant.id, order_id: order.id, scanned_code: "BH-SLK-NVY")

        expect(result.success?).to be true
        expect(result.data&.matched_sku).to eq("BH-SLK-NVY")
        expect(order.reload.status).to eq("packing")
      end
    end

    context "when scanned code does not match SKU" do
      it "fails verification and returns mismatch error message" do
        result = service.call(merchant_id: merchant.id, order_id: order.id, scanned_code: "WRONG-SKU-999")

        expect(result.success?).to be false
        expect(result.error).to include("SKU MISMATCH")
        expect(order.reload.status).to eq("received")
      end
    end

    context "when scanned code is blank" do
      it "returns failure validation message" do
        result = service.call(merchant_id: merchant.id, order_id: order.id, scanned_code: "   ")

        expect(result.success?).to be false
        expect(result.error).to include("cannot be blank")
      end
    end
  end
end
