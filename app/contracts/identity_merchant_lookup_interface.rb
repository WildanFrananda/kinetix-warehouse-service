# typed: strict

module IdentityMerchantLookupInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(principal_id: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def merchant_info(principal_id); end
end
