# typed: false
# frozen_string_literal: true

RSpec.shared_context "identity resolves merchants" do
  let(:identity_stub) { instance_double(Identity::V1::IdentityService::Stub) }

  before do
    allow(Identity::V1::IdentityService::Stub).to receive(:new).and_return(identity_stub)

    allow(identity_stub).to receive(:get_merchant_info) do |request|
      merchant = Merchant.all.find { |m| identity_user_id_for(m.api_key) == request.user_id }

      if merchant
        Identity::V1::GetMerchantInfoResponse.new(
          user_id: request.user_id,
          store_name: merchant.name,
          business_registration_number: "REG-#{merchant.id}",
          tax_id: "TAX-#{merchant.id}",
          status: "verified"
        )
      else
        Identity::V1::GetMerchantInfoResponse.new(status: "not_found")
      end
    end
  end

  def identity_user_id_for(api_key)
    digits = api_key.to_s.scan(/\d+/).first
    digits ? digits.to_i : 101
  end
end
