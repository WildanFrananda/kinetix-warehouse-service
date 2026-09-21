# typed: false

require "rails_helper"
require "identity/v1/identity_pb"

RSpec.describe "identity.v1.GetMerchantInfoResponse" do
  let(:fields) { ::Identity::V1::GetMerchantInfoResponse.descriptor.map(&:name) }

  it "carries identity's decision about trading" do
    expect(fields).to include("may_sell")
  end

  it "names the merchant principal, so this service need not assume the token's subject is one" do
    expect(fields).to include("merchant_principal_id")
  end

  it "still says whether it found anything at all" do
    expect(fields).to include("found")
  end

  it "keeps status, which is evidence for a human and not a rule to re-implement" do
    expect(fields).to include("status")
  end
end
