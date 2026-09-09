# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "sample"

module Kinetix
  module Metrics
    module MetricInterface
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.returns(String) }
      def name; end

      sig { abstract.returns(String) }
      def help; end

      sig { abstract.returns(String) }
      def type; end

      sig { abstract.returns(T::Array[Sample]) }
      def samples; end
    end
  end
end
