# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "metric_interface"
require_relative "sample"

module Kinetix
  module Metrics
    class MirroredCounter
      extend T::Sig
      include MetricInterface

      sig { override.returns(String) }
      attr_reader :name

      sig { override.returns(String) }
      attr_reader :help

      sig { returns(T::Array[String]) }
      attr_reader :label_names

      sig { params(name: String, help: String, label_names: T::Array[String]).void }
      def initialize(name:, help:, label_names:)
        @name = name
        @help = help
        @label_names = T.let(label_names.map(&:dup).map(&:freeze).freeze, T::Array[String])
        @sorted_label_names = T.let(@label_names.sort.freeze, T::Array[String])
        @mutex = T.let(Mutex.new, Mutex)
        @series = T.let(nil, T.nilable(T::Array[Sample]))
      end

      sig { override.returns(String) }
      def type
        "counter"
      end

      sig { params(series: T::Array[Sample]).void }
      def replace(series)
        series.each do |sample|
          next if sample.labels.keys.sort == @sorted_label_names

          raise ArgumentError,
                "#{@name} is labelled by #{@label_names.join(', ')}, published series carries #{sample.labels.keys.join(', ')}"
        end

        renamed = series.map { |sample| Sample.new(name: @name, labels: sample.labels, value: sample.value) }
        @mutex.synchronize { @series = renamed }
      end

      sig { void }
      def unknown
        @mutex.synchronize { @series = nil }
      end

      sig { override.returns(T::Array[Sample]) }
      def samples
        @mutex.synchronize { @series&.dup || [] }
      end
    end
  end
end
