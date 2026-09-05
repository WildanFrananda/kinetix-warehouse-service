# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Identity::GrpcClient do
  PRINCIPAL = "11111111-2222-3333-4444-555555555555"

  subject(:client) { described_class.new(host: "identity.test:50052") }

  let(:grpc_stub) { instance_double(Identity::V1::IdentityService::Stub) }

  before do
    allow(Identity::V1::IdentityService::Stub).to receive(:new).and_return(grpc_stub)
  end

  describe "#get_user_profile" do
    let(:response) do
      Identity::V1::GetUserProfileResponse.new(
        found: true,
        principal_id: PRINCIPAL,
        email: "siti@example.com",
        full_name: "Siti Rahma",
        phone_number: "081987654321",
        street_address: "Jl. Mawar No. 10",
        city: "Bandung",
        postal_code: "40115",
        kind: "PRINCIPAL_KIND_CUSTOMER"
      )
    end

    it "returns every field identity sent" do
      allow(grpc_stub).to receive(:get_user_profile).and_return(response)

      expect(client.get_user_profile(principal_id: PRINCIPAL)).to eq(
        principal_id: PRINCIPAL,
        email: "siti@example.com",
        full_name: "Siti Rahma",
        phone_number: "081987654321",
        street_address: "Jl. Mawar No. 10",
        city: "Bandung",
        postal_code: "40115",
        kind: "PRINCIPAL_KIND_CUSTOMER"
      )
    end

    it "asks identity for the principal it was given" do
      allow(grpc_stub).to receive(:get_user_profile) do |req|
        expect(req.principal_id).to eq(PRINCIPAL)
        response
      end

      client.get_user_profile(principal_id: PRINCIPAL)
    end

    it "returns nil when identity does not know the principal" do
      allow(grpc_stub).to receive(:get_user_profile)
        .and_return(Identity::V1::GetUserProfileResponse.new(found: false))

      expect(client.get_user_profile(principal_id: PRINCIPAL)).to be_nil
    end

    it "returns nil when identity is unreachable" do
      allow(grpc_stub).to receive(:get_user_profile).and_raise(GRPC::Unavailable)

      expect(Rails.logger).to receive(:error).with(/GetUserProfile failed for #{PRINCIPAL}/)
      expect(client.get_user_profile(principal_id: PRINCIPAL)).to be_nil
    end
  end
end
