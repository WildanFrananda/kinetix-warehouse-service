# spec/requests/scanner_spec.rb
require "rails_helper"

RSpec.describe "Scanner Controller", type: :request do
  let!(:merchant) { Merchant.create!(code: "BH-001", name: "Boutique Hijab Premium", cutoff_hour: 14) }
  let!(:staff) do
    StaffUser.create!(
      merchant: merchant,
      name: "Budi Hendra",
      email: "budi@boutiquehijab.id",
      role: "Warehouse Manager",
      password: "secret123"
    )
  end

  let!(:task) do
    FulfillmentTask.create!(
      merchant: merchant,
      order_number: "ORD-BH-1001",
      status: "received",
      same_day_cutoff_at: Time.current + 2.hours
    )
  end

  let!(:task_line) do
    task.fulfillment_task_lines.create!(
      sku: "BH-SLK-NVY",
      quantity: 1,
      bin_location: "Rak A-01, Bin 12"
    )
  end

  before do
    post login_path, params: { email: "budi@boutiquehijab.id", password: "secret123" }
  end

  describe "GET /scan" do
    context "without a fulfillment_task_id parameter" do
      it "renders the empty state card asking staff to select an order from queue" do
        get scanner_path(merchant_id: merchant.id)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("NO ORDER SELECTED FOR SCANNING")
        expect(response.body).to include("Select Order in Order Queue")
      end
    end

    context "with an explicit fulfillment_task_id parameter" do
      it "renders target order details, bin location, and item SKU" do
        get scanner_path(merchant_id: merchant.id, fulfillment_task_id: task.id)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("ORD-BH-1001")
        expect(response.body).to include("Rak A-01, Bin 12")
        expect(response.body).to include("BH-SLK-NVY")
      end
    end
  end

  describe "POST /scan/verify" do
    it "processes valid barcode scan, updates status, and redirects back to scanner" do
      post verify_scan_path(merchant_id: merchant.id), params: { fulfillment_task_id: task.id, scanned_code: "BH-SLK-NVY" }

      expect(response).to redirect_to(scanner_path(merchant_id: merchant.id, fulfillment_task_id: task.id))
      follow_redirect!
      expect(response.body).to include("MATCHED")
      expect(task.reload.status).to eq("packing")
    end

    it "handles barcode scan mismatch and redirects back with alert message" do
      post verify_scan_path(merchant_id: merchant.id), params: { fulfillment_task_id: task.id, scanned_code: "INVALID-SKU" }

      expect(response).to redirect_to(scanner_path(merchant_id: merchant.id, fulfillment_task_id: task.id))
      follow_redirect!
      expect(response.body).to include("SKU MISMATCH")
    end
  end
end
