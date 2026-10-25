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
  let(:order) { FakePackedReport.new }

  before do
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(order)
  end

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

        it "does not refuse it for its standing, since scanning finishes a paid order; the task is not its own" do
          scan("GAMIS-RED-M", with: other)

          expect(response).to have_http_status(:not_found)
          expect(task.reload.status).to eq("received")
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

    it "refuses a customer token, even for a principal this service has a merchant row for" do
      customer = bearer(access_token(principal_id: principal_id, role: "customer"))
      scan("GAMIS-RED-M", with: customer)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("NOT_A_SELLER")
      expect(identity_client.asked).to be_empty
      expect(task.reload.status).to eq("received")
    end
  end

  describe "a matching scan" do
    it "packs a one-line task, since that scan has matched every line, and says what matched" do
      scan("GAMIS-RED-M")

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["matched"]).to eq("sku")
      expect(json["matched_code"]).to eq("GAMIS-RED-M")
      expect(json["matched_sku"]).to eq("GAMIS-RED-M")
      expect(json["lines_remaining"]).to eq(0)
      expect(json["new_status"]).to eq("packed")
      expect(task.reload.status).to eq("packed")
    end

    it "tells order once the scan packs the parcel, so a courier is dispatched" do
      scan("GAMIS-RED-M")

      expect(order.packed).to eq([ task.order_number ])
      json = JSON.parse(response.body)
      expect(json["order_notified"]).to be(true)
      expect(json["dispatch_ref"]).to eq("DISPATCH-1")
    end

    it "does not care about the case the scanner reports" do
      scan("gamis-red-m")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["matched_code"]).to eq("GAMIS-RED-M")
      expect(task.reload.status).to eq("packed")
    end
  end

  describe "a task of two lines" do
    let!(:second) { create(:fulfillment_task_line, fulfillment_task: task, sku: "HIJAB-BLK-L") }

    it "stays packing after the first matching scan and is packed only after the second" do
      scan("GAMIS-RED-M")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["new_status"]).to eq("packing")
      expect(response.parsed_body["lines_remaining"]).to eq(1)
      expect(response.parsed_body["message"]).to include("1 line left")
      expect(task.reload.status).to eq("packing")
      expect(order.packed).to be_empty

      scan("HIJAB-BLK-L")

      expect(response.parsed_body["new_status"]).to eq("packed")
      expect(response.parsed_body["lines_remaining"]).to eq(0)
      expect(response.parsed_body["order_notified"]).to be(true)
      expect(task.reload.status).to eq("packed")
      expect(order.packed).to eq([ task.order_number ])
    end

    it "counts a line once, however often it is scanned" do
      scan("GAMIS-RED-M")
      scan("GAMIS-RED-M")

      expect(response).to have_http_status(:ok)
      expect(task.reload.status).to eq("packing")
      expect(order.packed).to be_empty
      json = response.parsed_body
      expect(json["line_already_scanned"]).to be(true)
      expect(json["lines_remaining"]).to eq(1)
      expect(json["new_status"]).to eq("packing")
      expect(json["order_notified"]).to be(false)
    end

    it "records which line each scan matched" do
      scan("HIJAB-BLK-L")

      expect(second.reload.scanned_at).to be_present
      expect(line.reload.scanned_at).to be_nil
    end

    it "is not packed by scanning its order number, which matches no line" do
      scan("GAMIS-RED-M")
      scan(task.order_number)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["matched"]).to eq("order_number")
      expect(json["matched_sku"]).to be_nil
      expect(json["lines_remaining"]).to eq(1)
      expect(task.reload.status).to eq("packing")
    end

    it "cannot be set packed by hand while a line is unscanned" do
      scan("GAMIS-RED-M")

      patch "/api/v1/fulfillment_tasks/#{task.id}/status", params: { status: "packed" }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("1 line")
      expect(task.reload.status).to eq("packing")
      expect(order.packed).to be_empty
    end

    it "packs a task whose last line another scan matched without packing it, and tells order once" do
      scan("GAMIS-RED-M")
      FulfillmentTaskLine.where(id: second.id).update_all(scanned_at: Time.current)

      scan("HIJAB-BLK-L")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["new_status"]).to eq("packed")
      expect(response.parsed_body["line_already_scanned"]).to be(true)
      expect(order.packed).to eq([ task.order_number ])
    end
  end

  describe "a scan of a packed parcel" do
    before do
      scan("GAMIS-RED-M")
      order.packed.clear
    end

    it "changes nothing and does not report the parcel to order again" do
      scan("GAMIS-RED-M")

      expect(response).to have_http_status(:ok)
      expect(order.packed).to be_empty
      json = response.parsed_body
      expect(json["new_status"]).to eq("packed")
      expect(json["line_already_scanned"]).to be(true)
      expect(json["lines_remaining"]).to eq(0)
      expect(json["order_notified"]).to be(false)
    end

    it "names the tracking number as what matched, not the order number" do
      create(:shipping_label, fulfillment_task: task, awb_number: "KNX-20261022-TRACK001", reprint_count: 0)

      scan("KNX-20261022-TRACK001")

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["matched"]).to eq("tracking_number")
      expect(json["matched_code"]).to eq("KNX-20261022-TRACK001")
      expect(json["matched_sku"]).to be_nil
      expect(json["message"]).not_to include(task.order_number)
      expect(order.packed).to be_empty
    end

    it "keeps it on the queue until its label is printed, and prints it" do
      create(:shipping_label, fulfillment_task: task, awb_number: "KNX-20261022-TRACK002", reprint_count: 0)

      get "/api/v1/fulfillment_tasks/queue", headers: headers
      expect(response.parsed_body.map { |card| card["id"] }).to eq([ task.id ])
      expect(response.parsed_body.first["lines"].first["scanned"]).to be(true)

      post "/api/v1/fulfillment_tasks/#{task.id}/label", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["print_count"]).to eq(1)

      get "/api/v1/fulfillment_tasks/queue", headers: headers
      expect(response.parsed_body).to be_empty
    end
  end

  describe "the order number" do
    it "starts packing, because it is on the paperwork, but matches no line" do
      scan(task.order_number)

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json["matched"]).to eq("order_number")
      expect(json["matched_code"]).to eq(task.order_number)
      expect(json["matched_sku"]).to be_nil
      expect(json["lines_remaining"]).to eq(1)
      expect(task.reload.status).to eq("packing")
      expect(order.packed).to be_empty
    end
  end

  describe "a scan that does not match" do
    it "refuses it and leaves the task where it was" do
      scan("SOMETHING-ELSE")

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to include("GAMIS-RED-M")
      expect(task.reload.status).to eq("received")
    end

    it "refuses a blank code rather than treating it as a match" do
      scan("   ")

      expect(response).to have_http_status(:unprocessable_content)
      expect(task.reload.status).to eq("received")
    end
  end

  describe "whose task it is" do
    it "will not scan another merchant's task, even with a valid token" do
      other_merchant = create(:merchant)
      other_task = create(:fulfillment_task, merchant: other_merchant, status: "received")

      post "/api/v1/fulfillment_tasks/#{other_task.id}/verify_scan",
           params: { scanned_code: "GAMIS-RED-M" }, headers: headers

      expect(response).to have_http_status(:not_found)
      expect(other_task.reload.status).to eq("received")
    end
  end
end
