# typed: strict
# frozen_string_literal: true

module Kinetix
  module LowStockThreshold
    extend T::Sig

    VARIABLE = "WAREHOUSE_LOW_STOCK_THRESHOLD"

    sig { params(env: T::Hash[String, String]).returns(Integer) }
    def self.from_env(env)
      raw = env.fetch(VARIABLE) { raise "#{VARIABLE} is required and has no default." }
      threshold = T.let(Integer(raw, exception: false), T.nilable(Integer))
      raise "#{VARIABLE}=#{raw} is not a whole number of units, zero or more." if threshold.nil? || threshold.negative?

      threshold
    end
  end
end
