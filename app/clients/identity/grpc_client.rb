# typed: strict
# frozen_string_literal: true

require "identity/v1/identity_services_pb"
require Rails.root.join("lib/kinetix/request_id").to_s
require Rails.root.join("lib/kinetix/service_identity").to_s
require Rails.root.join("lib/kinetix/metrics/grpc_client_recorder").to_s

module Identity
  class GrpcClient
    extend T::Sig
    include IdentityMerchantLookupInterface

    PEER = "identity"
    GRPC_METHOD = T.let(
      "/#{::Identity::V1::IdentityService::Service.service_name}/GetMerchantInfo",
      String
    )

    sig { returns(String) }
    attr_reader :host

    sig { params(host: String).void }
    def initialize(host: ENV.fetch("IDENTITY_GRPC_HOST"))
      @host = T.let(host, String)
    end

    sig { override.params(principal_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def merchant_info(principal_id)
      return nil if principal_id.empty?

      stub = ::Identity::V1::IdentityService::Stub.new(
        @host,
        Kinetix::ServiceIdentity.new.channel_credentials,
        timeout: 5
      )

      req = ::Identity::V1::GetMerchantInfoRequest.new(principal_id: principal_id)

      res = Kinetix::Metrics::GrpcClientRecorder.call(peer: PEER, grpc_method: GRPC_METHOD) do
        stub.get_merchant_info(req, metadata: Kinetix::RequestId.metadata)
      end

      return nil unless res.found

      {
        may_sell: res.may_sell,
        merchant_principal_id: res.merchant_principal_id,
        store_name: res.store_name,
        status: res.status.to_s
      }
    rescue GRPC::BadStatus, GRPC::Core::CallError, SocketError, IOError => e
      raise Identity::Unavailable.new(principal_id, e.message)
    end
  end
end
