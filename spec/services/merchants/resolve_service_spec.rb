# typed: false

require "rails_helper"

RSpec.describe Merchants::ResolveService do
  let(:caller_principal) { "aaaaaaaa-0000-4000-8000-000000000001" }
  let(:merchant_principal) { "bbbbbbbb-0000-4000-8000-000000000002" }

  def resolve(identity)
    described_class.new(
      merchant_repository: MerchantRepository.new,
      identity_client: identity
    ).call(principal_id: caller_principal)
  end

  context "when identity names a merchant principal that is not the caller's" do
    let(:identity) { FakeIdentityClient.new(merchant_principal_id: merchant_principal) }

    it "answers with that merchant's existing row instead of failing to create it again" do
      existing = Merchant.create!(principal_id: merchant_principal, cutoff_hour: 10)

      standing = resolve(identity)

      expect(standing.merchant.id).to eq(existing.id)
      expect(Merchant.where(principal_id: merchant_principal).count).to eq(1)
      expect(Merchant.find_by(principal_id: caller_principal)).to be_nil
    end

    it "projects that merchant's row the first time" do
      standing = resolve(identity)

      expect(standing.merchant.principal_id).to eq(merchant_principal)
    end
  end

  it "keeps identity's trading decision beside the row" do
    standing = resolve(FakeIdentityClient.new(may_sell: false, status: "MERCHANT_STATUS_SUSPENDED"))

    expect(standing.may_sell).to be(false)
    expect(standing.merchant.principal_id).to eq(caller_principal)
  end

  it "answers nothing for a principal identity knows no merchant for, and projects no row" do
    expect(resolve(FakeIdentityClient.new(known: false))).to be_nil
    expect(Merchant.count).to eq(0)
  end
end
