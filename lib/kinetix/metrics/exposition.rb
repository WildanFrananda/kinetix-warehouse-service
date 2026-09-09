# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "sample"

module Kinetix
  module Metrics
    module Exposition
      extend T::Sig

      CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8"

      sig { params(value: String).returns(String) }
      def self.escape(value)
        value.gsub(/[\\\n"]/) do |character|
          case character
          when "\\" then "\\\\"
          when "\n" then "\\n"
          else "\\\""
          end
        end
      end

      sig { params(value: Float).returns(String) }
      def self.number(value)
        return "+Inf" if value == Float::INFINITY
        return "-Inf" if value == -Float::INFINITY
        return "NaN" if value.nan?

        integral = value.truncate
        value - integral == 0.0 ? integral.to_s : value.to_s
      end

      sig { params(labels: T::Hash[String, String]).returns(String) }
      def self.labels(labels)
        return "" if labels.empty?

        pairs = labels.map { |name, value| "#{name}=\"#{escape(value)}\"" }
        "{#{pairs.join(',')}}"
      end

      sig { params(sample: Sample).returns(String) }
      def self.line(sample)
        "#{sample.name}#{labels(sample.labels)} #{number(sample.value)}"
      end
    end
  end
end
