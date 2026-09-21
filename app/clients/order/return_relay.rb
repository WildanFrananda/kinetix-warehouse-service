# typed: strict
# frozen_string_literal: true

module Order
  module ReturnRelay
    extend T::Sig
    extend T::Helpers
    interface!

    sig do
      abstract.params(
        merchant_principal_id: String,
        order_number: String,
        reason: String
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def open_return(merchant_principal_id:, order_number:, reason:); end

    sig do
      abstract.params(
        merchant_principal_id: String,
        return_number: String,
        lines: T::Array[T::Hash[Symbol, T.untyped]],
        bin_code: String,
        received_at: Time
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def return_goods_received(merchant_principal_id:, return_number:, lines:, bin_code:, received_at:); end
  end
end
