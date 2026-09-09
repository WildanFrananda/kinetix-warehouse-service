# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "counter"
require_relative "gauge"
require_relative "histogram"
require_relative "mirror"
require_relative "mirrored_counter"
require_relative "registry"
require_relative "sample"

module Kinetix
  module Metrics
    class Collection
      extend T::Sig

      SERVICE = "kinetix-warehouse-service"
      GRPC_SERVER_CALLS = "kinetix_grpc_server_calls_total"
      MIRROR_UP = "kinetix_metrics_mirror_up"
      UNKNOWN_VERSION = "unknown"

      sig { returns(Registry) }
      attr_reader :registry

      sig { returns(Counter) }
      attr_reader :http_requests

      sig { returns(Histogram) }
      attr_reader :http_request_duration

      sig { returns(Counter) }
      attr_reader :grpc_client_calls

      sig { params(mirror: Mirror, service: String, version: String).void }
      def initialize(mirror: Mirror.new, service: SERVICE, version: Collection.version)
        @mirror = T.let(mirror, T.nilable(Mirror))
        @registry = T.let(Registry.new, Registry)
        @mirror_reachable = T.let(nil, T.nilable(T::Boolean))

        @http_requests = T.let(
          Counter.new(
            name: "kinetix_http_requests_total",
            help: "HTTP requests served, by method, matched route template and response status.",
            label_names: %w[method route status]
          ),
          Counter
        )

        @http_request_duration = T.let(
          Histogram.new(
            name: "kinetix_http_request_duration_seconds",
            help: "Time to serve an HTTP request, in seconds.",
            label_names: %w[method route]
          ),
          Histogram
        )

        @grpc_client_calls = T.let(
          Counter.new(
            name: "kinetix_grpc_client_calls_total",
            help: "gRPC calls this service made to another service, by peer, method and status code.",
            label_names: %w[peer grpc_method grpc_code]
          ),
          Counter
        )

        @build_info = T.let(
          Gauge.new(
            name: "kinetix_build_info",
            help: "Always 1. The labels name the build that answered this scrape.",
            label_names: %w[service version]
          ),
          Gauge
        )

        @grpc_server_calls_mirror = T.let(
          MirroredCounter.new(
            name: GRPC_SERVER_CALLS,
            help: "gRPC calls this service served, by method and status code, as last published " \
                  "by its gRPC process.",
            label_names: %w[grpc_method grpc_code]
          ),
          MirroredCounter
        )

        @mirror_up = T.let(
          Gauge.new(
            name: MIRROR_UP,
            help: "1 when the gRPC process's published counters were readable and fresh on this " \
                  "scrape, 0 when they were not. At 0 the gRPC counters are absent rather than zero.",
            label_names: []
          ),
          Gauge
        )

        @registry.register(@http_requests)
        @registry.register(@http_request_duration)
        @registry.register(@grpc_client_calls)
        @registry.register(@grpc_server_calls_mirror)
        @registry.register(@mirror_up)
        @registry.register(@build_info)

        @build_info.set({ "service" => service, "version" => version }, 1.0)
      end

      sig { returns(Counter) }
      def serve_grpc_server_calls
        counter = Counter.new(
          name: GRPC_SERVER_CALLS,
          help: "gRPC calls this service served, by method and status code.",
          label_names: %w[grpc_method grpc_code]
        )

        @registry.replace(counter)
        @registry.unregister(MIRROR_UP)
        @mirror = nil
        counter
      end

      sig { returns(String) }
      def scrape
        refresh_mirror
        @registry.render
      end

      sig { returns(String) }
      def self.version
        from_env = ENV["KINETIX_SERVICE_VERSION"]
        return from_env unless from_env.nil? || from_env.empty?

        path = File.expand_path("../../../VERSION", __dir__)
        return UNKNOWN_VERSION unless File.readable?(path)

        contents = File.read(path).strip
        contents.empty? ? UNKNOWN_VERSION : contents
      rescue StandardError
        UNKNOWN_VERSION
      end

      private

      sig { void }
      def refresh_mirror
        mirror = @mirror
        return if mirror.nil?

        samples = T.let(nil, T.nilable(T::Array[Sample]))
        reason = T.let(nil, T.nilable(String))

        begin
          samples = mirror.read(%w[grpc_method grpc_code])
          reason = "no fresh publication at #{Mirror::KEY}" if samples.nil?
        rescue StandardError => e
          reason = "#{e.class}: #{e.message}"
        end

        if samples.nil?
          @grpc_server_calls_mirror.unknown
          @mirror_up.set({}, 0.0)
        else
          @grpc_server_calls_mirror.replace(samples)
          @mirror_up.set({}, 1.0)
        end

        log_mirror_state(!samples.nil?, reason)
      end

      sig { params(reachable: T::Boolean, reason: T.nilable(String)).void }
      def log_mirror_state(reachable, reason)
        return if @mirror_reachable == reachable

        @mirror_reachable = reachable
        if reachable
          Rails.logger.info("gRPC server metrics mirror is readable again")
        else
          Rails.logger.warn("gRPC server metrics mirror unreadable, #{GRPC_SERVER_CALLS} withheld: #{reason}")
        end
      end
    end
  end
end
