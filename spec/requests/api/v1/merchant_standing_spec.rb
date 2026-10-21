# typed: false

require "rails_helper"

RSpec.describe "a merchant's standing is identity's answer on every request", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-4333-8444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id, cutoff_hour: 14) }
  let(:seller) { bearer(access_token(principal_id: principal_id, role: "seller")) }

  def queue(with: seller)
    get "/api/v1/fulfillment_tasks/queue", headers: with
  end

  def set_cutoff(hour, with: seller)
    patch "/api/v1/merchants/#{merchant.id}", params: { cutoff_hour: hour }, headers: with
  end

  describe "a merchant this service already has a row for" do
    it "still asks identity, every time" do
      queue
      queue

      expect(response).to have_http_status(:ok)
      expect(identity_client.asked).to eq([ principal_id, principal_id ])
    end

    context "once identity no longer knows it as a merchant" do
      let(:identity_client) { FakeIdentityClient.new(known: false) }

      it "refuses its seller calls" do
        queue

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq("NOT_A_MERCHANT")
      end
    end

    context "once identity says it may not trade" do
      let(:identity_client) { FakeIdentityClient.new(may_sell: false, status: "MERCHANT_STATUS_SUSPENDED") }

      it "still lets it finish what buyers have already paid for" do
        queue

        expect(response).to have_http_status(:ok)
      end

      it "refuses to change how its store runs" do
        set_cutoff(9)

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq("MERCHANT_NOT_TRADING")
        expect(merchant.reload.cutoff_hour).to eq(14)
      end
    end

    context "when identity cannot be asked" do
      let(:identity_client) { FakeIdentityClient.new(unavailable: true) }

      it "answers 503 rather than deciding from its own row" do
        queue

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to eq("IDENTITY_UNAVAILABLE")
      end
    end
  end

  describe "the role on the token" do
    %w[customer courier admin].each do |role|
      it "refuses a #{role} token without asking identity" do
        queue(with: bearer(access_token(principal_id: principal_id, role: role)))

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq("NOT_A_SELLER")
        expect(identity_client.asked).to be_empty
      end
    end
  end

  describe "GET /api/v1/merchants/me" do
    it "names the caller's own merchant row, which PATCH /merchants/{id} needs" do
      get "/api/v1/merchants/me", headers: seller

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "id" => merchant.id,
        "principal_id" => principal_id,
        "cutoff_hour" => 14,
        "may_sell" => true
      )
    end

    it "projects the row for a merchant identity vouches for and this service has never seen" do
      newcomer = "99999999-9999-4999-8999-999999999999"

      get "/api/v1/merchants/me", headers: bearer(access_token(principal_id: newcomer, role: "seller"))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(Merchant.find_by(principal_id: newcomer).id)
    end
  end
end
