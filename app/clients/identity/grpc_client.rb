# typed: strict
# frozen_string_literal: true

require "grpc"
require_relative "../../../lib/generated/identity/v1/identity_service_services_pb"
require Rails.root.join("lib/kinetix/service_identity").to_s

module Identity
  class GrpcClient
    extend T::Sig

    sig { returns(String) }
    attr_reader :host

    sig { params(host: String).void }
    def initialize(host: ENV.fetch("IDENTITY_GRPC_HOST"))
      @host = host
    end

    sig { params(user_id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def get_user_profile(user_id:)
      stub = Identity::V1::IdentityService::Stub.new(
        @host,
        Kinetix::ServiceIdentity.new.channel_credentials,
        timeout: 5
      )

      req = Identity::V1::GetUserProfileRequest.new(user_id: user_id)
      res = stub.get_user_profile(req)

      return nil if res.email.empty? && res.full_name.empty?

      {
        user_id: res.user_id,
        email: res.email,
        full_name: res.full_name,
        phone_number: res.phone_number,
        street_address: res.street_address,
        city: res.city,
        postal_code: res.postal_code,
        role: res.role
      }
    rescue StandardError => e
      Rails.logger.error("gRPC IdentityService.GetUserProfile failed for User #{user_id}: #{e.message}")
      nil
    end
  end
end
