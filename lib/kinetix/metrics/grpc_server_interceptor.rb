# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"
require_relative "counter"
require_relative "grpc_status_code"

module Kinetix
  module Metrics
    class GrpcServerInterceptor < GRPC::ServerInterceptor
      extend T::Sig

      OK = "OK"
      UNKNOWN_METHOD = "(unknown)"

      sig { params(counter: Counter).void }
      def initialize(counter)
        @counter = counter
        @mutex = T.let(Mutex.new, Mutex)
        @names = T.let({}, T::Hash[String, String])
        super()
      end

      sig { params(service: T.untyped).void }
      def declare(service)
        klass = service.is_a?(Class) ? service : service.class
        klass.rpc_descs.each_key do |rpc|
          @counter.initialize_series("grpc_method" => "/#{klass.service_name}/#{rpc}", "grpc_code" => OK)
        end
      rescue StandardError => e
        Rails.logger.warn("cannot pre-declare gRPC metrics for #{service}: #{e.class}: #{e.message}")
      end

      sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
      def request_response(request:, call:, method:, &blk)
        around(method) { yield }
      end

      sig { params(call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
      def client_streamer(call:, method:, &blk)
        around(method) { yield }
      end

      sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
      def server_streamer(request:, call:, method:, &blk)
        around(method) { yield }
      end

      sig { params(requests: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
      def bidi_streamer(requests:, call:, method:, &blk)
        around(method) { yield }
      end

      private

      sig { params(method: T.untyped, blk: T.untyped).returns(T.untyped) }
      def around(method, &blk)
        result = yield
        record(method, OK)
        result
      rescue GRPC::BadStatus => e
        record(method, GrpcStatusCode.name_for(e.code))
        raise
      rescue StandardError
        record(method, GrpcStatusCode::UNKNOWN)
        raise
      end

      sig { params(method: T.untyped, code: String).void }
      def record(method, code)
        @counter.increment("grpc_method" => name_of(method), "grpc_code" => code)
      end

      sig { params(method: T.untyped).returns(String) }
      def name_of(method)
        klass = method.receiver.class
        cache_key = "#{klass}##{method.name}"
        cached = @mutex.synchronize { @names[cache_key] }
        return cached unless cached.nil?

        resolved = resolve(klass, method.name)
        @mutex.synchronize { @names[cache_key] = resolved }
        resolved
      end

      sig { params(klass: T.untyped, ruby_name: T.untyped).returns(String) }
      def resolve(klass, ruby_name)
        rpc = klass.rpc_descs.keys.find do |key|
          GRPC::GenericService.underscore(key.to_s) == ruby_name.to_s
        end
        return UNKNOWN_METHOD if rpc.nil?

        "/#{klass.service_name}/#{rpc}"
      rescue StandardError
        UNKNOWN_METHOD
      end
    end
  end
end
