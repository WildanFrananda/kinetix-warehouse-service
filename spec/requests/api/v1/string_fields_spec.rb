# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "string fields sent as another JSON type", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:staff) { "aaaaaaaa-1111-4222-8333-666666666666" }
  let(:owner) { "bbbbbbbb-1111-4222-8333-666666666666" }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:admin) { bearer(access_token(principal_id: staff, role: "admin")).merge(json) }
  let(:seller) { bearer(access_token(principal_id: owner)).merge(json) }
  let!(:bin) { WarehouseBin.create!(bin_code: "A-01-1", zone: "A", shelf_level: 1) }

  def not_strings(text)
    [ [ text ], { "value" => text }, 12, true ]
  end

  describe "POST /bins" do
    %i[bin_code zone].each do |field|
      it "refuses a #{field} that is not a string, and writes no bin" do
        not_strings("B-02-1").each do |value|
          post "/api/v1/bins", params: { bin_code: "B-02-1", zone: "B" }.merge(field => value).to_json, headers: admin

          expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
          expect(response.parsed_body["error"]).to eq("#{field} must be a string")
        end

        expect(WarehouseBin.pluck(:bin_code)).to eq([ "A-01-1" ])
        expect(bin.reload.zone).to eq("A")
      end
    end
  end

  describe "POST /stock_receipts" do
    let(:receipt) do
      {
        bin_code: "A-01-1",
        sku: "SKU-1",
        quantity: 5,
        idempotency_key: "RCV-1",
        merchant_principal_id: owner,
        note: "first delivery"
      }
    end

    %i[idempotency_key merchant_principal_id bin_code sku note].each do |field|
      it "refuses a #{field} that is not a string with INVALID_#{field.upcase}, and books nothing" do
        not_strings(receipt[field]).each do |value|
          post "/api/v1/stock_receipts", params: receipt.merge(field => value).to_json, headers: admin

          expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
          expect(response.parsed_body["error"]).to eq("INVALID_#{field.upcase}")
          expect(response.parsed_body["message"]).to eq("#{field} must be a string")
        end

        expect(StockReceipt.count).to eq(0)
        expect(BinInventory.count).to eq(0)
      end
    end
  end

  describe "POST /stock_adjustments" do
    let!(:inventory) do
      BinInventory.create!(
        warehouse_bin: bin,
        sku: "SKU-1",
        quantity: 10,
        reserved_quantity: 0,
        merchant_principal_id: owner
      )
    end
    let(:adjustment) do
      {
        bin_code: "A-01-1",
        sku: "SKU-1",
        quantity_delta: -1,
        reason: "DAMAGE",
        idempotency_key: "ADJ-1",
        merchant_principal_id: owner,
        note: "crushed carton"
      }
    end

    %i[idempotency_key merchant_principal_id bin_code sku reason note].each do |field|
      it "refuses a #{field} that is not a string with INVALID_#{field.upcase}, and moves nothing" do
        not_strings(adjustment[field]).each do |value|
          post "/api/v1/stock_adjustments", params: adjustment.merge(field => value).to_json, headers: admin

          expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
          expect(response.parsed_body["error"]).to eq("INVALID_#{field.upcase}")
          expect(response.parsed_body["message"]).to eq("#{field} must be a string")
        end

        expect(StockAdjustment.count).to eq(0)
        expect(inventory.reload.quantity).to eq(10)
      end
    end
  end

  describe "the seller's task routes" do
    let!(:merchant) { create(:merchant, principal_id: owner) }
    let!(:task) { create(:fulfillment_task, merchant: merchant, status: "received") }
    let(:order) { FakePackedReport.new }
    let(:relay) { FakeReturnRelay.new }

    before do
      create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M")
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(order)
    end

    it "refuses a status that is not a string, and moves nothing" do
      not_strings("packing").each do |value|
        patch "/api/v1/fulfillment_tasks/#{task.id}/status", params: { status: value }.to_json, headers: seller

        expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("status must be a string")
      end

      expect(task.reload.status).to eq("received")
    end

    it "refuses a scanned_code that is not a string, and scans nothing" do
      not_strings("GAMIS-RED-M").each do |value|
        post "/api/v1/fulfillment_tasks/#{task.id}/verify_scan",
             params: { scanned_code: value }.to_json,
             headers: seller

        expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("scanned_code must be a string")
      end

      expect(task.reload.status).to eq("received")
    end

    it "refuses a return reason that is not a string, and tells order nothing" do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)

      not_strings("Wrong size").each do |value|
        post "/api/v1/fulfillment_tasks/#{task.id}/returns", params: { reason: value }.to_json, headers: seller

        expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("reason must be a string")
      end

      expect(relay.opened).to be_empty
    end

    it "refuses returned goods whose bin_code is not a string, and tells order nothing" do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)

      not_strings("A-01-1").each do |value|
        post "/api/v1/returns/RMA-1/received",
             params: { bin_code: value, lines: [ { sku: "GAMIS-RED-M", quantity: 1 } ] }.to_json,
             headers: seller

        expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("bin_code must be a string")
      end

      expect(relay.received).to be_empty
    end

    it "refuses a returned line whose sku is not a string, and tells order nothing" do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)

      not_strings("GAMIS-RED-M").each do |value|
        post "/api/v1/returns/RMA-1/received",
             params: { bin_code: "A-01-1", lines: [ { sku: value, quantity: 1 } ] }.to_json,
             headers: seller

        expect(response).to have_http_status(:unprocessable_content), "#{value.inspect} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("Every line needs a SKU, written as a string")
      end

      expect(relay.received).to be_empty
    end
  end

  describe "a string with a NUL character, which the database cannot store" do
    let!(:merchant) { create(:merchant, principal_id: owner) }
    let!(:task) { create(:fulfillment_task, merchant: merchant, status: "received", order_number: "ORD-NUL-1") }
    let(:relay) { FakeReturnRelay.new }

    before do
      create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M")
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(FakePackedReport.new)
    end

    it "is refused as a bin code with 422, not a 500, and writes no bin" do
      post "/api/v1/bins", params: { bin_code: "B\u0000B", zone: "B" }.to_json, headers: admin

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("bin_code must not contain a NUL character")
      expect(WarehouseBin.count).to eq(1)
    end

    it "is refused in a receipt's note and sku with the field's code, and books nothing" do
      receipt = {
        bin_code: "A-01-1",
        sku: "SKU-1",
        quantity: 5,
        idempotency_key: "RCV-NUL",
        merchant_principal_id: owner
      }

      post "/api/v1/stock_receipts", params: receipt.merge(note: "x\u0000y").to_json, headers: admin

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_NOTE")
      expect(response.parsed_body["message"]).to eq("note must not contain a NUL character")

      post "/api/v1/stock_receipts", params: receipt.merge(sku: "SKU\u00001").to_json, headers: admin

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("INVALID_SKU")
      expect(StockReceipt.count).to eq(0)
    end

    it "is refused as an order number to look a task up by with 400, not a 500" do
      get "/api/v1/fulfillment_tasks", params: { order_number: "ORD\u0000NUL-1" }, headers: seller

      expect(response).to have_http_status(:bad_request)
    end

    it "is refused as a scanned code or a status with 422, and moves nothing" do
      post "/api/v1/fulfillment_tasks/#{task.id}/verify_scan",
           params: { scanned_code: "GAMIS\u0000RED-M" }.to_json,
           headers: seller

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("scanned_code must not contain a NUL character")

      patch "/api/v1/fulfillment_tasks/#{task.id}/status", params: { status: "pack\u0000ing" }.to_json, headers: seller

      expect(response).to have_http_status(:unprocessable_content)
      expect(task.reload.status).to eq("received")
    end

    it "is refused in a returned line's sku, and tells order nothing" do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)

      post "/api/v1/returns/RMA-1/received",
           params: { bin_code: "A-01-1", lines: [ { sku: "GAMIS\u0000RED-M", quantity: 1 } ] }.to_json,
           headers: seller

      expect(response).to have_http_status(:unprocessable_content)
      expect(relay.received).to be_empty
    end
  end
end
