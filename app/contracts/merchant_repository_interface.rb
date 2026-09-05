# typed: strict

module MerchantRepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(id: Integer).returns(T.nilable(Merchant)) }
  def find_by_id(id); end

  sig { abstract.params(principal_id: String).returns(T.nilable(Merchant)) }
  def find_by_principal_id(principal_id); end
end
