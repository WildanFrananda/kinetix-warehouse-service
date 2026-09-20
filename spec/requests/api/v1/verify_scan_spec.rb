# typed: false

require "rails_helper"

# The packer's barcode scan. Fulfillment::VerifyScanService has always done this work; its only
# caller used to be a page this service rendered itself, so deleting the dashboard would have taken
# the capability with it. These assert the endpoint that replaced the page.
RSpec.describe "Api::V1::FulfillmentTasks#verify_scan", type: :request do
  include_context "identity issues tokens"

  let(:principal_id) { "11111111-2222-3333-4444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, status: "received") }
  let!(:line) { create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M") }
  let(:headers) { bearer(access_token(principal_id: principal_id)) }

  def scan(code, with: headers)
    post "/api/v1/fulfillment_tasks/#{task.id}/verify_scan",
         params: { scanned_code: code }, headers: with
  end

  describe "who may scan" do
    it "refuses a request with no token" do
      scan("GAMIS-RED-M", with: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token whose principal owns no merchant here" do
      other = bearer(access_token(principal_id: "99999999-9999-9999-9999-999999999999"))
      scan("GAMIS-RED-M", with: other)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a customer, who has no business on the packing floor" do
      customer = bearer(access_token(principal_id: principal_id, role: "customer"))
      scan("GAMIS-RED-M", with: customer)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "a matching scan" do
    it "advances a received task to packing and says what matched" do
      scan("GAMIS-RED-M")

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["matched_sku"]).to eq("GAMIS-RED-M")
      expect(json["new_status"]).to eq("packing")
      expect(task.reload.status).to eq("packing")
    end

    it "advances a packing task to packed on the second scan" do
      scan("GAMIS-RED-M")
      scan("GAMIS-RED-M")

      expect(JSON.parse(response.body)["new_status"]).to eq("packed")
      expect(task.reload.status).to eq("packed")
    end

    it "accepts the order number as well as the SKU, because both are on the paperwork" do
      scan(task.order_number)

      expect(response).to have_http_status(:ok)
      expect(task.reload.status).to eq("packing")
    end

    it "does not care about the case the scanner reports" do
      scan("gamis-red-m")

      expect(response).to have_http_status(:ok)
      expect(task.reload.status).to eq("packing")
    end
  end

  describe "a scan that does not match" do
    it "refuses it and leaves the task where it was" do
      scan("SOMETHING-ELSE")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("GAMIS-RED-M")
      expect(task.reload.status).to eq("received")
    end

    it "refuses a blank code rather than treating it as a match" do
      scan("   ")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.status).to eq("received")
    end
  end

  describe "whose task it is" do
    it "will not scan another merchant's task, even with a valid token" do
      other_merchant = create(:merchant)
      other_task = create(:fulfillment_task, merchant: other_merchant, status: "received")

      post "/api/v1/fulfillment_tasks/#{other_task.id}/verify_scan",
           params: { scanned_code: "GAMIS-RED-M" }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_task.reload.status).to eq("received")
    end
  end
end
