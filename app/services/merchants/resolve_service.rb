# typed: strict

module Merchants
  class ResolveService < BaseService
    extend T::Sig

    sig { returns(MerchantRepositoryInterface) }
    attr_reader :merchant_repository

    sig { returns(IdentityMerchantLookupInterface) }
    attr_reader :identity_client

    sig do
      params(
        merchant_repository: MerchantRepositoryInterface,
        identity_client: IdentityMerchantLookupInterface
      ).void
    end
    def initialize(
      merchant_repository: T.let(Container[:merchant_repository], MerchantRepositoryInterface),
      identity_client: T.let(Container[:identity_grpc_client], IdentityMerchantLookupInterface)
    )
      super()
      @merchant_repository = merchant_repository
      @identity_client = identity_client
    end

    sig { params(principal_id: String).returns(T.nilable(Standing)) }
    def call(principal_id:)
      info = identity_client.merchant_info(principal_id)
      return nil if info.nil?

      named = info[:merchant_principal_id].to_s
      key = named.empty? ? principal_id : named
      merchant = merchant_repository.find_by_principal_id(key) || merchant_repository.project(key)

      Standing.new(merchant: merchant, may_sell: info[:may_sell] == true)
    end
  end
end
