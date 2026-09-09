# typed: strict
# frozen_string_literal: true

require "grpc"
require "identity/v1/identity_services_pb"
require Rails.root.join("lib/kinetix/request_id").to_s
require Rails.root.join("lib/kinetix/service_identity").to_s
require Rails.root.join("lib/kinetix/metrics/grpc_client_recorder").to_s

module Identity
  class GrpcClient
    extend T::Sig

    PEER = "identity"
    GRPC_METHOD = T.let(
      "/#{Identity::V1::IdentityService::Service.service_name}/GetUserProfile",
      String
    )

    sig { returns(String) }
    attr_reader :host

    sig { params(host: String).void }
    def initialize(host: ENV.fetch("IDENTITY_GRPC_HOST"))
      @host = host
    end

    sig { params(principal_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def get_user_profile(principal_id:)
      stub = Identity::V1::IdentityService::Stub.new(
        @host,
        Kinetix::ServiceIdentity.new.channel_credentials,
        timeout: 5
      )

      req = Identity::V1::GetUserProfileRequest.new(principal_id: principal_id)
      res = Kinetix::Metrics::GrpcClientRecorder.call(peer: PEER, grpc_method: GRPC_METHOD) do
        stub.get_user_profile(req, metadata: Kinetix::RequestId.metadata)
      end

      return nil unless res.found

      {
        principal_id: res.principal_id,
        email: res.email,
        full_name: res.full_name,
        phone_number: res.phone_number,
        street_address: res.street_address,
        city: res.city,
        postal_code: res.postal_code,
        kind: res.kind.to_s
      }
    rescue StandardError => e
      Rails.logger.error("gRPC IdentityService.GetUserProfile failed for #{principal_id}: #{e.message}")
      nil
    end
  end
end
