# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "values warehouse refuses itself before asking order", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-3333-4444-888888888888" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, order_number: "ORD-RETURN-7") }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:headers) { bearer(access_token(principal_id: principal_id)).merge(json) }
  let(:relay) { FakeReturnRelay.new }
  let(:goods) { { bin_code: "A-01-1", lines: [ { sku: "GAMIS-RED-M", quantity: 1 } ] } }

  before do
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)
  end

  describe "the return number in the path of returned goods" do
    [
      "RMA-1",
      "12abc",
      "rma-20261027-0a1b2c3d",
      "RMA-20261027-0a1b2c3d",
      "RMA-20261027-0A1B2C3",
      "RMA-20261027-0A1B2C3DE",
      "RMA-2026102-0A1B2C3D",
      "RMA-20261027-0A1B2C3G",
      "RMA-20261027_0A1B2C3D",
      "RMA-20261027-0A1B2C3D%00",
      "RMA-20261027-0A1B%002C3D",
      "RMA-20261027-0A1B2C3D%0A",
      "%20RMA-20261027-0A1B2C3D",
      "RMA-20261027-0A1B2C3D#{'0' * 44}"
    ].each do |spelling|
      it "is 404 for #{spelling.inspect}, which order cannot have issued, and order is not asked" do
        post "/api/v1/returns/#{spelling}/received", params: goods.to_json, headers: headers

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq("error" => "Return not found")
        expect(relay.received).to be_empty
      end
    end

    it "relays a number in order's own format" do
      post "/api/v1/returns/RMA-20261027-0A1B2C3D/received", params: goods.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(relay.received.first[:return_number]).to eq("RMA-20261027-0A1B2C3D")
    end

    it "is read after the caller's standing, so a token that is not a seller's is still 403" do
      buyer = bearer(access_token(principal_id: principal_id, role: "customer")).merge(json)

      post "/api/v1/returns/RMA-1/received", params: goods.to_json, headers: buyer

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("NOT_A_SELLER")
    end

    it "is read before the body, so an unusable body on a number order never issued is still 404" do
      post "/api/v1/returns/RMA-1/received", params: { bin_code: [ "A" ] }.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a returned line's SKU" do
    it "is refused over 128 characters, the longest SKU warehouse keeps, before order is told" do
      lines = [ { sku: "S" * 129, quantity: 1 } ]

      post "/api/v1/returns/RMA-20261027-0A1B2C3D/received",
           params: { bin_code: "A-01-1", lines: lines }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "Every line's SKU must be at most 128 characters")
      expect(relay.received).to be_empty
    end

    it "is refused when it is only whitespace order would not read as a SKU" do
      lines = [ { sku: " 　", quantity: 1 } ]

      post "/api/v1/returns/RMA-20261027-0A1B2C3D/received",
           params: { bin_code: "A-01-1", lines: lines }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "Every line needs a SKU, written as a string")
      expect(relay.received).to be_empty
    end
  end

  describe "a return's reason" do
    it "is refused when it is only whitespace order would not read as a reason" do
      post "/api/v1/fulfillment_tasks/#{task.id}/returns",
           params: { reason: "  　" }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq("error" => "Reason cannot be blank")
      expect(relay.opened).to be_empty
    end
  end
end
