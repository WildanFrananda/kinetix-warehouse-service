# typed: strict

module Inventory
  class StockFilter < T::Struct
    const :sku, T.nilable(String)
    const :bin_code, T.nilable(String)
    const :merchant_principal_id, T.nilable(String)
  end
end
