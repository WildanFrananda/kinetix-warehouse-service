# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "metric_interface"
require_relative "sample"

module Kinetix
  module Metrics
    class Histogram
      extend T::Sig
      include MetricInterface

      DEFAULT_BUCKETS = T.let(
        [ 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0 ].freeze,
        T::Array[Float]
      )

      sig { override.returns(String) }
      attr_reader :name

      sig { override.returns(String) }
      attr_reader :help

      sig { returns(T::Array[String]) }
      attr_reader :label_names

      sig do
        params(
          name: String,
          help: String,
          label_names: T::Array[String],
          buckets: T::Array[Float]
        ).void
      end
      def initialize(name:, help:, label_names:, buckets: DEFAULT_BUCKETS)
        @name = name
        @help = help
        @label_names = T.let(label_names.map(&:dup).map(&:freeze).freeze, T::Array[String])
        @sorted_label_names = T.let(@label_names.sort.freeze, T::Array[String])
        @buckets = T.let(buckets.sort.freeze, T::Array[Float])
        @mutex = T.let(Mutex.new, Mutex)
        @bucket_counts = T.let({}, T::Hash[T::Array[String], T::Array[Float]])
        @sums = T.let({}, T::Hash[T::Array[String], Float])
        @counts = T.let({}, T::Hash[T::Array[String], Float])
      end

      sig { override.returns(String) }
      def type
        "histogram"
      end

      sig { params(labels: T::Hash[String, String], value: Float).void }
      def observe(labels, value)
        key = key_for(labels)
        index = @buckets.index { |bound| value <= bound }

        @mutex.synchronize do
          counts = T.let(@bucket_counts[key] || Array.new(@buckets.size, 0.0), T::Array[Float])
          @bucket_counts[key] = counts

          counts[index] = T.must(counts[index]) + 1.0 unless index.nil?
          @sums[key] = (@sums[key] || 0.0) + value
          @counts[key] = (@counts[key] || 0.0) + 1.0
        end
      end

      sig { override.returns(T::Array[Sample]) }
      def samples
        bucket_counts, sums, counts = @mutex.synchronize do
          [ @bucket_counts.transform_values(&:dup), @sums.dup, @counts.dup ]
        end

        bucket_counts.flat_map do |key, per_bucket|
          series_for(key, per_bucket, T.must(sums[key]), T.must(counts[key]))
        end
      end

      private

      sig do
        params(
          key: T::Array[String],
          per_bucket: T::Array[Float],
          sum: Float,
          count: Float
        ).returns(T::Array[Sample])
      end
      def series_for(key, per_bucket, sum, count)
        labels = labels_for(key)
        samples = T.let([], T::Array[Sample])
        cumulative = 0.0

        @buckets.each_with_index do |bound, index|
          cumulative += T.must(per_bucket[index])
          samples << Sample.new(
            name: "#{@name}_bucket",
            labels: labels.merge("le" => bound.to_s),
            value: cumulative
          )
        end

        samples << Sample.new(name: "#{@name}_bucket", labels: labels.merge("le" => "+Inf"), value: count)
        samples << Sample.new(name: "#{@name}_sum", labels: labels, value: sum)
        samples << Sample.new(name: "#{@name}_count", labels: labels, value: count)
        samples
      end

      sig { params(labels: T::Hash[String, String]).returns(T::Array[String]) }
      def key_for(labels)
        unless labels.keys.sort == @sorted_label_names
          raise ArgumentError, "#{@name} is labelled by #{@label_names.join(', ')}, got #{labels.keys.join(', ')}"
        end

        @label_names.map { |label_name| T.must(labels[label_name]) }
      end

      sig { params(key: T::Array[String]).returns(T::Hash[String, String]) }
      def labels_for(key)
        labels = T.let({}, T::Hash[String, String])
        @label_names.each_with_index { |label_name, index| labels[label_name] = T.must(key[index]) }
        labels
      end
    end
  end
end
