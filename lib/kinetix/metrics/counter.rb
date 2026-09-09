# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "metric_interface"
require_relative "sample"

module Kinetix
  module Metrics
    class Counter
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
        @values = T.let({}, T::Hash[T::Array[String], Float])
      end

      sig { override.returns(String) }
      def type
        "counter"
      end

      sig { params(labels: T::Hash[String, String]).void }
      def increment(labels)
        key = key_for(labels)
        @mutex.synchronize { @values[key] = (@values[key] || 0.0) + 1.0 }
      end

      sig { params(labels: T::Hash[String, String]).void }
      def initialize_series(labels)
        key = key_for(labels)
        @mutex.synchronize { @values[key] ||= 0.0 }
      end

      sig { override.returns(T::Array[Sample]) }
      def samples
        snapshot = @mutex.synchronize { @values.dup }
        snapshot.map do |key, value|
          Sample.new(name: @name, labels: labels_for(key), value: value)
        end
      end

      private

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
