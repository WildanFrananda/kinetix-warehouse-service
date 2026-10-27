# typed: strict
# frozen_string_literal: true

module Rpc
  module StringLimits
    extend T::Sig

    sig { params(field: String, values: T::Array[String], limit: Integer).void }
    def self.refuse_longer!(field, values, limit)
      return if values.all? { |value| value.length <= limit }

      raise GRPC::InvalidArgument.new("#{field} must be at most #{limit} characters")
    end
  end
end
