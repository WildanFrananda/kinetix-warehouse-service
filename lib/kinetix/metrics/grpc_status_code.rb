# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"

module Kinetix
  module Metrics
    module GrpcStatusCode
      extend T::Sig

      UNKNOWN = "UNKNOWN"

      NAMES = T.let(
        GRPC::Core::StatusCodes.constants.each_with_object({}) do |constant, names|
          code = GRPC::Core::StatusCodes.const_get(constant)
          names[Integer(code)] = constant.to_s
        end.freeze,
        T::Hash[Integer, String]
      )

      sig { params(code: T.untyped).returns(String) }
      def self.name_for(code)
        NAMES.fetch(Integer(code), UNKNOWN)
      rescue StandardError
        UNKNOWN
      end
    end
  end
end
