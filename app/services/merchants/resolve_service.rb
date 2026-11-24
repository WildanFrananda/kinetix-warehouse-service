# typed: strict

module Merchants
  class ResolveService < BaseService
    extend T::Sig

    sig { returns(FulfillmentSettingRepositoryInterface) }
    attr_reader :setting_repository

    sig { returns(IdentityMerchantLookupInterface) }
    attr_reader :identity_client

    sig do
      params(
        setting_repository: FulfillmentSettingRepositoryInterface,
        identity_client: IdentityMerchantLookupInterface
      ).void
    end
    def initialize(
      setting_repository: T.let(Container[:fulfillment_setting_repository], FulfillmentSettingRepositoryInterface),
      identity_client: T.let(Container[:identity_grpc_client], IdentityMerchantLookupInterface)
    )
      super()
      @setting_repository = setting_repository
      @identity_client = identity_client
    end

    sig { params(principal_id: String).returns(T.nilable(Standing)) }
    def call(principal_id:)
      info = identity_client.merchant_info(principal_id)
      return nil if info.nil?

      named = info[:merchant_principal_id].to_s
      key = named.empty? ? principal_id : named
      setting = setting_repository.find_by_principal_id(key) || setting_repository.project(key)

      Standing.new(setting: setting, may_sell: info[:may_sell] == true)
    end
  end
end
