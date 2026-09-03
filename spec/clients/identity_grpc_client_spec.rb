# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Identity::GrpcClient do
  subject(:client) { described_class.new(host: "identity.test:50052") }

  let(:grpc_stub) { instance_double(Identity::V1::IdentityService::Stub) }

  before do
    allow(Identity::V1::IdentityService::Stub).to receive(:new).and_return(grpc_stub)
  end

  describe "#get_user_profile" do
    let(:response) do
      Identity::V1::GetUserProfileResponse.new(
        user_id: 42,
        email: "siti@example.com",
        full_name: "Siti Rahma",
        phone_number: "081987654321",
        street_address: "Jl. Mawar No. 10",
        city: "Bandung",
        postal_code: "40115",
        role: "customer"
      )
    end

    it "returns every field identity sent" do
      allow(grpc_stub).to receive(:get_user_profile).and_return(response)

      expect(client.get_user_profile(user_id: 42)).to eq(
        user_id: 42,
        email: "siti@example.com",
        full_name: "Siti Rahma",
        phone_number: "081987654321",
        street_address: "Jl. Mawar No. 10",
        city: "Bandung",
        postal_code: "40115",
        role: "customer"
      )
    end

    it "asks identity for the user id it was given" do
      allow(grpc_stub).to receive(:get_user_profile) do |req|
        expect(req.user_id).to eq(42)
        response
      end

      client.get_user_profile(user_id: 42)
    end

    it "returns nil when identity answers with an empty profile" do
      allow(grpc_stub).to receive(:get_user_profile)
        .and_return(Identity::V1::GetUserProfileResponse.new(user_id: 42))

      expect(client.get_user_profile(user_id: 42)).to be_nil
    end

    it "returns nil when identity is unreachable" do
      allow(grpc_stub).to receive(:get_user_profile).and_raise(GRPC::Unavailable)

      expect(Rails.logger).to receive(:error).with(/GetUserProfile failed for User 42/)
      expect(client.get_user_profile(user_id: 42)).to be_nil
    end
  end

  describe "#get_merchant_by_api_key" do
    let(:response) do
      Identity::V1::GetMerchantInfoResponse.new(
        user_id: 7,
        store_name: "Boutique Hijab Premium",
        business_registration_number: "REG-778899",
        tax_id: "TAX-112233",
        status: "verified"
      )
    end

    it "returns the merchant and echoes the key back" do
      allow(grpc_stub).to receive(:get_merchant_info).and_return(response)

      expect(client.get_merchant_by_api_key(api_key: "luxe_7")).to eq(
        user_id: 7,
        store_name: "Boutique Hijab Premium",
        business_registration_number: "REG-778899",
        tax_id: "TAX-112233",
        status: "verified",
        api_key: "luxe_7"
      )
    end

    it "does not dial identity for an empty key" do
      expect(Identity::V1::IdentityService::Stub).not_to receive(:new)

      expect(client.get_merchant_by_api_key(api_key: "")).to be_nil
    end

    it "returns nil when identity does not know the merchant" do
      allow(grpc_stub).to receive(:get_merchant_info)
        .and_return(Identity::V1::GetMerchantInfoResponse.new(status: "not_found"))

      expect(client.get_merchant_by_api_key(api_key: "luxe_7")).to be_nil
    end

    it "returns nil when the merchant has no store name" do
      allow(grpc_stub).to receive(:get_merchant_info)
        .and_return(Identity::V1::GetMerchantInfoResponse.new(user_id: 7, status: "verified"))

      expect(client.get_merchant_by_api_key(api_key: "luxe_7")).to be_nil
    end

    it "returns nil when identity is unreachable" do
      allow(grpc_stub).to receive(:get_merchant_info).and_raise(GRPC::Unavailable)

      expect(Rails.logger).to receive(:error).with(/GetMerchantInfo failed/)
      expect(client.get_merchant_by_api_key(api_key: "luxe_7")).to be_nil
    end

    # DEFECT, pinned here so it cannot be forgotten. The client does not send the API key to
    # identity at all — it scrapes the first run of digits out of the key and sends that as a
    # user id, falling back to 101 when the key has no digits. So "anything_7" resolves to
    # merchant 7, and every key without a digit resolves to the same account.
    #
    # This is not fixed here because the whole merchant-API-key mechanism is being deleted: the
    # platform will have no third-party integrations, and first-party callers move to
    # identity-issued RS256 tokens. These two specs exist so the behaviour is visible in the
    # suite rather than buried, and so that deletion has to be deliberate — when the mechanism
    # goes, these fail and force the decision.
    describe "the user id it actually sends (defect: awaiting the API-key removal)" do
      it "scrapes the first digits out of the key" do
        allow(grpc_stub).to receive(:get_merchant_info) do |req|
          expect(req.user_id).to eq(7)
          response
        end

        client.get_merchant_by_api_key(api_key: "anything_7_at_all")
      end

      it "falls back to 101 for a key with no digits" do
        allow(grpc_stub).to receive(:get_merchant_info) do |req|
          expect(req.user_id).to eq(101)
          response
        end

        client.get_merchant_by_api_key(api_key: "no_digits_here")
      end
    end
  end
end
