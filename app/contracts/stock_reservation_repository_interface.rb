# typed: strict

module StockReservationRepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(merchant_principal_id: String, order_number: String).returns(T::Hash[String, String]) }
  def held_bin_codes(merchant_principal_id:, order_number:); end
end
