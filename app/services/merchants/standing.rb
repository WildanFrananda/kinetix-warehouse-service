# typed: strict

module Merchants
  class Standing < T::Struct
    const :setting, FulfillmentSetting
    const :may_sell, T::Boolean
  end
end
