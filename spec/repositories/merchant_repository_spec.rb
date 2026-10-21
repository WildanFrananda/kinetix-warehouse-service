# typed: false

require "rails_helper"

RSpec.describe MerchantRepository do
  it "returns the row a concurrent request created instead of raising on the uniqueness check" do
    principal = "cccccccc-0000-4000-8000-000000000003"
    repository = described_class.new
    winner = Merchant.create!(principal_id: principal)

    expect(repository.project(principal).id).to eq(winner.id)
  end
end
