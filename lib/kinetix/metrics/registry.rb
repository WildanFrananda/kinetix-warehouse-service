# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "exposition"
require_relative "metric_interface"

module Kinetix
  module Metrics
    class Registry
      extend T::Sig

      sig { void }
      def initialize
        @mutex = T.let(Mutex.new, Mutex)
        @metrics = T.let({}, T::Hash[String, MetricInterface])
      end

      sig { params(metric: MetricInterface).void }
      def register(metric)
        @mutex.synchronize do
          raise ArgumentError, "#{metric.name} is already registered" if @metrics.key?(metric.name)

          @metrics[metric.name] = metric
        end
      end

      sig { params(metric: MetricInterface).void }
      def replace(metric)
        @mutex.synchronize do
          raise ArgumentError, "#{metric.name} is not registered" unless @metrics.key?(metric.name)

          @metrics[metric.name] = metric
        end
      end

      sig { params(name: String).void }
      def unregister(name)
        @mutex.synchronize do
          raise ArgumentError, "#{name} is not registered" unless @metrics.key?(name)

          @metrics.delete(name)
        end
      end

      sig { returns(String) }
      def render
        metrics = @mutex.synchronize { @metrics.values.dup }
        body = +""

        metrics.each do |metric|
          samples = metric.samples
          next if samples.empty?

          body << "# HELP #{metric.name} #{metric.help}\n"
          body << "# TYPE #{metric.name} #{metric.type}\n"
          samples.each { |sample| body << Exposition.line(sample) << "\n" }
        end

        body
      end
    end
  end
end
