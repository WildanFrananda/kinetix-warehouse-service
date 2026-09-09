# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "puma"
require_relative "../logger_io"
require_relative "collection"
require_relative "exposition"
require_relative "http_middleware"

module Kinetix
  module Metrics
    class HttpServer
      extend T::Sig

      PATH = "/metrics"
      DEFAULT_PORT = 3000
      DEFAULT_HOST = "0.0.0.0"
      MAX_THREADS = 2

      sig { params(collection: Collection, port: Integer, host: String).void }
      def initialize(collection:, port: HttpServer.port, host: DEFAULT_HOST)
        @collection = collection
        @port = port
        @host = host
        @server = T.let(nil, T.untyped)
      end

      sig { returns(Integer) }
      def self.port
        Integer(ENV.fetch("METRICS_PORT", DEFAULT_PORT.to_s))
      end

      sig { returns(T::Boolean) }
      def start
        server = Puma::Server.new(
          HttpMiddleware.new(rack_app, known_paths: [ PATH ], collection: @collection),
          nil,
          {
            min_threads: 0,
            max_threads: MAX_THREADS,
            log_writer: Puma::LogWriter.new(
              Kinetix::LoggerIo.new(logger: Rails.logger),
              Kinetix::LoggerIo.new(logger: Rails.logger, severity: :error)
            )
          }
        )
        server.add_tcp_listener(@host, @port)
        server.run
        @server = server
        Rails.logger.info("metrics endpoint listening on #{@host}:#{@port}#{PATH}")
        true
      rescue StandardError => e
        Rails.logger.error("metrics endpoint could not bind #{@host}:#{@port}: #{e.class}: #{e.message}")
        false
      end

      sig { void }
      def stop
        server = @server
        return if server.nil?

        server.stop(true)
        @server = nil
      end

      private

      sig { returns(T.proc.params(env: T::Hash[String, T.untyped]).returns(T::Array[T.untyped])) }
      def rack_app
        lambda do |env|
          next not_found unless env["PATH_INFO"] == PATH
          next not_found unless %w[GET HEAD].include?(env["REQUEST_METHOD"])

          begin
            body = @collection.scrape
            [ 200, { "content-type" => Exposition::CONTENT_TYPE, "cache-control" => "no-store" }, [ body ] ]
          rescue StandardError => e
            Rails.logger.error("metrics scrape failed: #{e.class}: #{e.message}")
            [ 500, { "content-type" => "text/plain; charset=utf-8" }, [ "metrics unavailable\n" ] ]
          end
        end
      end

      sig { returns(T::Array[T.untyped]) }
      def not_found
        [ 404, { "content-type" => "text/plain; charset=utf-8" }, [ "not found\n" ] ]
      end
    end
  end
end
