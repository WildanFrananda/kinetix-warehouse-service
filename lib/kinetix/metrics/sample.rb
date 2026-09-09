# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Kinetix
  module Metrics
    class Sample < T::Struct
      const :name, String
      const :labels, T::Hash[String, String]
      const :value, Float
    end
  end
end
