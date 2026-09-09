# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../metrics"
require_relative "route_template"

module Kinetix
  module Metrics
    class HttpMiddleware
      extend T::Sig

      KNOWN_METHODS = T.let(
        %w[GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT].freeze,
        T::Array[String]
      )
      OTHER_METHOD = "OTHER"
      SERVER_ERROR_STATUS = "500"
      UNKNOWN_STATUS = "(unknown)"

      sig do
        params(
          app: T.untyped,
          known_paths: T.nilable(T::Array[String]),
          collection: T.nilable(Collection)
        ).void
      end
      def initialize(app, known_paths: nil, collection: nil)
        @app = app
        @known_paths = T.let(known_paths&.dup&.freeze, T.nilable(T::Array[String]))
        @collection = T.let(collection, T.nilable(Collection))
      end

      sig { params(env: T::Hash[String, T.untyped]).returns(T.untyped) }
      def call(env)
        started = monotonic

        begin
          response = @app.call(env)
        rescue StandardError
          record(env, SERVER_ERROR_STATUS, started)
          raise
        end

        record(env, status_of(response), started)
        response
      end

      private

      sig { params(response: T.untyped).returns(String) }
      def status_of(response)
        Integer(response[0]).to_s
      rescue StandardError
        UNKNOWN_STATUS
      end

      sig { returns(Float) }
      def monotonic
        Float(Process.clock_gettime(Process::CLOCK_MONOTONIC))
      end

      sig { params(env: T::Hash[String, T.untyped], status: String, started: Float).void }
      def record(env, status, started)
        elapsed = monotonic - started
        http_method = method_label(env)
        route = route_label(env)

        metrics = @collection || Kinetix::Metrics.collection
        metrics.http_requests.increment(
          "method" => http_method, "route" => route, "status" => status
        )
        metrics.http_request_duration.observe({ "method" => http_method, "route" => route }, elapsed)
      rescue StandardError => e
        log_dropped_sample(e)
      end

      sig { params(error: StandardError).void }
      def log_dropped_sample(error)
        Rails.logger&.warn("dropped an HTTP metric sample: #{error.class}: #{error.message}")
      rescue StandardError
        nil
      end

      sig { params(env: T::Hash[String, T.untyped]).returns(String) }
      def method_label(env)
        http_method = env["REQUEST_METHOD"].to_s
        KNOWN_METHODS.include?(http_method) ? http_method : OTHER_METHOD
      end

      sig { params(env: T::Hash[String, T.untyped]).returns(String) }
      def route_label(env)
        known_paths = @known_paths
        if known_paths.nil?
          return RouteTemplate.for_request(ActionDispatch::Request.new(env))
        end

        path = env["PATH_INFO"].to_s
        known_paths.include?(path) ? path : RouteTemplate::UNMATCHED
      end
    end
  end
end
