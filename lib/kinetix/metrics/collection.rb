# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "counter"
require_relative "gauge"
require_relative "histogram"
require_relative "registry"
require_relative "sample"

module Kinetix
  module Metrics
    class Collection
      extend T::Sig

      SERVICE = "kinetix-warehouse-service"
      GRPC_SERVER_CALLS = "kinetix_grpc_server_calls_total"
      UNKNOWN_VERSION = "unknown"

      SCRAPE_ROUTE = "/metrics"
      SCRAPE_METHOD = "GET"
      SCRAPE_STATUS = "200"

      sig { returns(Registry) }
      attr_reader :registry

      sig { returns(Counter) }
      attr_reader :http_requests

      sig { returns(Histogram) }
      attr_reader :http_request_duration

      sig { returns(Counter) }
      attr_reader :grpc_client_calls

      sig { params(service: String, version: String).void }
      def initialize(service: SERVICE, version: Collection.version)
        @registry = T.let(Registry.new, Registry)

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

        @registry.register(@http_requests)
        @registry.register(@http_request_duration)
        @registry.register(@grpc_client_calls)
        @registry.register(@build_info)

        @build_info.set({ "service" => service, "version" => version }, 1.0)
        initialize_scrape_series
      end

      sig { returns(Counter) }
      def serve_grpc_server_calls
        counter = Counter.new(
          name: GRPC_SERVER_CALLS,
          help: "gRPC calls this service served, by method and status code.",
          label_names: %w[grpc_method grpc_code]
        )

        @registry.register(counter)
        counter
      end

      sig { returns(String) }
      def scrape
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
      def initialize_scrape_series
        @http_requests.initialize_series(
          "method" => SCRAPE_METHOD, "route" => SCRAPE_ROUTE, "status" => SCRAPE_STATUS
        )
        @http_request_duration.initialize_series(
          "method" => SCRAPE_METHOD, "route" => SCRAPE_ROUTE
        )
      end
    end
  end
end
