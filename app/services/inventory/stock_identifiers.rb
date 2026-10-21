# typed: strict
# frozen_string_literal: true

module Inventory
  module StockIdentifiers
    extend T::Sig

    sig { params(sku: String).returns(T::Boolean) }
    def self.sku?(sku)
      !sku.strip.empty? && sku.length <= StockOperation::MAX_SKU_LENGTH
    end
  end
end
