# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Kinetix
  class AccessClaims < T::Struct
    extend T::Sig

    const :principal_id, String
    const :user_id, Integer
    const :email, String
    const :role, String

    class Malformed < StandardError; end

    sig { params(payload: T::Hash[String, T.untyped]).returns(Kinetix::AccessClaims) }
    def self.from_payload(payload)
      new(
        principal_id: text(payload, "sub"),
        user_id: number(payload, "uid"),
        email: text(payload, "email"),
        role: text(payload, "role")
      )
    end

    sig { params(payload: T::Hash[String, T.untyped], name: String).returns(String) }
    private_class_method def self.text(payload, name)
      value = payload[name]
      raise Malformed, "claim '#{name}' is missing or not a string" unless value.is_a?(String)

      value
    end

    sig { params(payload: T::Hash[String, T.untyped], name: String).returns(Integer) }
    private_class_method def self.number(payload, name)
      value = payload[name]
      raise Malformed, "claim '#{name}' is missing or not an integer" unless value.is_a?(Integer)

      value
    end
  end
end
