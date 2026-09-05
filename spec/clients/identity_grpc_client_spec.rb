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
end
