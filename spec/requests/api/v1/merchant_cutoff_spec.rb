# typed: false

require "rails_helper"

# The same-day cutoff hour was editable only from a settings page this service rendered. The page is
# gone; the setting is a warehouse operating parameter, so it needs a way in that is not a page.
RSpec.describe "Api::V1::Merchants#update", type: :request do
  include_context "identity issues tokens"

  let(:principal_id) { "11111111-2222-3333-4444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id, cutoff_hour: 14) }
  let(:headers) { bearer(access_token(principal_id: principal_id)) }

  def set_cutoff(value, id: merchant.id, with: headers)
    patch "/api/v1/merchants/#{id}", params: { cutoff_hour: value }, headers: with
  end

  it "sets the cutoff hour" do
    set_cutoff(17)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["cutoff_hour"]).to eq(17)
    expect(merchant.reload.cutoff_hour).to eq(17)
  end

  it "accepts midnight, which is a real hour and not an absent value" do
    set_cutoff(0)

    expect(response).to have_http_status(:ok)
    expect(merchant.reload.cutoff_hour).to eq(0)
  end

  it "refuses a request with no token" do
    set_cutoff(17, with: {})

    expect(response).to have_http_status(:unauthorized)
    expect(merchant.reload.cutoff_hour).to eq(14)
  end

  it "refuses to change another merchant's record" do
    other = create(:merchant, cutoff_hour: 9)
    set_cutoff(17, id: other.id)

    expect(response).to have_http_status(:forbidden)
    expect(other.reload.cutoff_hour).to eq(9)
  end

  it "refuses an hour that is not one" do
    set_cutoff(25)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(merchant.reload.cutoff_hour).to eq(14)
  end

  it "refuses a word, rather than reading it as hour zero" do
    # to_i turns "banana" into 0, which is a valid hour and the wrong answer.
    set_cutoff("banana")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(merchant.reload.cutoff_hour).to eq(14)
  end

  it "refuses a missing value" do
    patch "/api/v1/merchants/#{merchant.id}", params: {}, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(merchant.reload.cutoff_hour).to eq(14)
  end
end
