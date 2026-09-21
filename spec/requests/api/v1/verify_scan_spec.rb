# typed: false

require "rails_helper"

RSpec.describe "Api::V1::FulfillmentTasks#verify_scan", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

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

    context "a principal this service has no merchant row for" do
      let(:other) { bearer(access_token(principal_id: "99999999-9999-9999-9999-999999999999")) }

      context "and identity knows no merchant for it" do
        let(:identity_client) { FakeIdentityClient.new(known: false) }

        it "refuses" do
          scan("GAMIS-RED-M", with: other)

          expect(response).to have_http_status(:forbidden)
          expect(identity_client.asked).to eq([ "99999999-9999-9999-9999-999999999999" ])
        end
      end

      context "and identity says that merchant may not trade" do
        let(:identity_client) { FakeIdentityClient.new(may_sell: false, status: "MERCHANT_STATUS_SUSPENDED") }

        it "refuses" do
          scan("GAMIS-RED-M", with: other)

          expect(response).to have_http_status(:forbidden)
        end
      end

      context "and identity could not be asked" do
        let(:identity_client) { FakeIdentityClient.new(unavailable: true) }

        it "says so, and does not decide" do
          scan("GAMIS-RED-M", with: other)

          expect(response).to have_http_status(:service_unavailable)
          expect(JSON.parse(response.body)["error"]).to eq("IDENTITY_UNAVAILABLE")
          expect(response.headers["Retry-After"]).to eq("15")
        end
      end

      context "and identity vouches for it" do
        it "projects the merchant and lets the scan through" do
          other_principal = "99999999-9999-9999-9999-999999999999"
          expect(Merchant.find_by(principal_id: other_principal)).to be_nil

          scan("GAMIS-RED-M", with: other)

          expect(Merchant.find_by(principal_id: other_principal)).not_to be_nil
        end
      end
    end

    it "does not read the role claim" do
      customer = bearer(access_token(principal_id: principal_id, role: "customer"))
      scan("GAMIS-RED-M", with: customer)

      expect(response).to have_http_status(:ok)
      expect(identity_client.asked).to be_empty
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
