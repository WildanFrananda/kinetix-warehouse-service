# typed: false

require "rails_helper"

RSpec.describe "merchants are projected, not registered", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee" }
  let(:headers) { bearer(access_token(principal_id: principal_id)) }

  it "has no registration endpoint" do
    expect {
      Rails.application.routes.recognize_path("/api/v1/merchants", method: :post)
    }.to raise_error(ActionController::RoutingError)

    expect(Rails.application.routes.recognize_path("/api/v1/merchants/1", method: :patch))
      .to include(controller: "api/v1/merchants", action: "update")
  end

  it "has nothing to invent: the row is a principal and a packing cutoff" do
    columns = Merchant.column_names

    expect(columns).not_to include("name")
    expect(columns).not_to include("code")
    expect(columns).to include("principal_id")
  end

  it "refuses to save a row with no principal behind it" do
    expect(Merchant.new(cutoff_hour: 12)).not_to be_valid
  end

  describe "the packing cutoff" do
    let!(:merchant) { create(:merchant, principal_id: principal_id, cutoff_hour: 14) }

    it "is still this service's to set" do
      patch "/api/v1/merchants/#{merchant.id}", params: { cutoff_hour: 9 }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(merchant.reload.cutoff_hour).to eq(9)
    end
  end
end
