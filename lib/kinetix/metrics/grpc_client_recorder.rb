# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"
require_relative "../metrics"
require_relative "grpc_status_code"

module Kinetix
  module Metrics
    module GrpcClientRecorder
      extend T::Sig

      OK = "OK"

      sig do
        type_parameters(:Result)
          .params(
            peer: String,
            grpc_method: String,
            blk: T.proc.returns(T.type_parameter(:Result))
          )
          .returns(T.type_parameter(:Result))
      end
      def self.call(peer:, grpc_method:, &blk)
        result = yield
        record(peer, grpc_method, OK)
        result
      rescue GRPC::BadStatus => e
        record(peer, grpc_method, GrpcStatusCode.name_for(e.code))
        raise
      rescue StandardError
        record(peer, grpc_method, GrpcStatusCode::UNKNOWN)
        raise
      end

      sig { params(peer: String, grpc_method: String).void }
      def self.declare(peer:, grpc_method:)
        Kinetix::Metrics.collection.grpc_client_calls.initialize_series(
          "peer" => peer, "grpc_method" => grpc_method, "grpc_code" => OK
        )
      end

      sig { params(peer: String, grpc_method: String, code: String).void }
      def self.record(peer, grpc_method, code)
        Kinetix::Metrics.collection.grpc_client_calls.increment(
          "peer" => peer, "grpc_method" => grpc_method, "grpc_code" => code
        )
      end
      private_class_method :record
    end
  end
end
