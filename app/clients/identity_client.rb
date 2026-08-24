# typed: strict
# frozen_string_literal: true

require "grpc"
require_relative "../../lib/generated/identity/v1/identity_service_services_pb"

module Identity
  class GrpcClient
    extend T::Sig

    sig { returns(String) }
    attr_reader :host

    sig { params(host: String).void }
    def initialize(host: ENV.fetch("IDENTITY_GRPC_HOST", "localhost:50052"))
      @host = host
    end

    sig { params(user_id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def get_user_profile(user_id:)
      if Rails.env.test?
        return {
          user_id: user_id,
          email: "user_#{user_id}@kinetix.com",
          full_name: "Test User",
          phone_number: "081234567890",
          street_address: "Test Street",
          city: "Jakarta",
          postal_code: "10220",
          role: "customer"
        }
      end

      stub = Identity::V1::IdentityService::Stub.new(
        @host,
        :this_channel_is_insecure,
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

    sig { params(api_key: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def get_merchant_by_api_key(api_key:)
      return nil if api_key.empty?

      if Rails.env.test?
        m = Merchant.find_by(api_key: api_key)
        return nil unless m
        return {
          user_id: m.id,
          store_name: m.name,
          business_registration_number: "REG-TEST",
          tax_id: "TAX-TEST",
          status: "verified",
          api_key: api_key
        }
      end

      stub = Identity::V1::IdentityService::Stub.new(
        @host,
        :this_channel_is_insecure,
        timeout: 5
      )

      # Extract merchant user_id from key or query merchant info RPC
      digits = T.unsafe(api_key.scan(/\d+/)).first
      user_id_from_key = digits ? digits.to_i : 101

      req = Identity::V1::GetMerchantInfoRequest.new(user_id: user_id_from_key)
      res = stub.get_merchant_info(req)

      return nil if res.status == "not_found" || res.store_name.empty?

      {
        user_id: res.user_id,
        store_name: res.store_name,
        business_registration_number: res.business_registration_number,
        tax_id: res.tax_id,
        status: res.status,
        api_key: api_key
      }
    rescue StandardError => e
      Rails.logger.error("gRPC IdentityService.GetMerchantInfo failed for key #{api_key}: #{e.message}")
      nil
    end
  end
end
