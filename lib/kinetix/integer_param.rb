# typed: strict
# frozen_string_literal: true

module Kinetix
  module IntegerParam
    extend T::Sig

    MIN_INT32 = -2_147_483_648
    MAX_INT32 = 2_147_483_647
    MAX_BIGINT = 9_223_372_036_854_775_807

    UNSIGNED = T.let(/\A[0-9]{1,10}\z/, Regexp)
    SIGNED = T.let(/\A[+-]?[0-9]{1,10}\z/, Regexp)
    ID = T.let(/\A[0-9]{1,19}\z/, Regexp)

    sig { params(value: T.untyped, signed: T::Boolean).returns(T.nilable(Integer)) }
    def self.parse(value, signed:)
      return value if value.is_a?(Integer)
      return nil unless value.is_a?(String)
      return nil unless (signed ? SIGNED : UNSIGNED).match?(value)

      Integer(value, 10)
    end

    sig { params(value: T.untyped).returns(T.nilable(Integer)) }
    def self.id(value)
      return nil unless value.is_a?(String) && ID.match?(value)

      id = Integer(value, 10)
      return nil unless id.between?(1, MAX_BIGINT)

      id
    end
  end
end
