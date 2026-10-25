# typed: strict
# frozen_string_literal: true

module Inventory
  module StockIdentifiers
    extend T::Sig

    sig { params(sku: String).returns(T::Boolean) }
    def self.sku?(sku)
      !sku.strip.empty? && sku.length <= StockOperation::MAX_SKU_LENGTH
    end

    sig { params(key: String).returns(T::Boolean) }
    def self.idempotency_key?(key)
      key.length <= StockOperation::MAX_KEY_LENGTH
    end

    sig { params(bin_code: String).returns(T::Boolean) }
    def self.bin_code?(bin_code)
      bin_code.length <= WarehouseBin::MAX_CODE_LENGTH
    end
  end
end
