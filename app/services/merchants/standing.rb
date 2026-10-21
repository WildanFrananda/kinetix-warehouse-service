# typed: strict

module Merchants
  class Standing < T::Struct
    const :merchant, Merchant
    const :may_sell, T::Boolean
  end
end
