# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"
require_relative "database_outage"
require_relative "request_id"

module Kinetix
  class ErrorStatusInterceptor < GRPC::ServerInterceptor
    extend T::Sig

    UNAVAILABLE_DETAIL = "warehouse could not reach its database; try again shortly"
    INTERNAL_DETAIL = "warehouse failed while handling this call"

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def request_response(request:, call:, method:, &blk)
      guard(method) { yield }
    end

    sig { params(call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def client_streamer(call:, method:, &blk)
      guard(method) { yield }
    end

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def server_streamer(request:, call:, method:, &blk)
      guard(method) { yield }
    end

    sig { params(requests: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def bidi_streamer(requests:, call:, method:, &blk)
      guard(method) { yield }
    end

    private

    sig { params(method: T.untyped, blk: T.proc.returns(T.untyped)).returns(T.untyped) }
    def guard(method, &blk)
      yield
    rescue GRPC::BadStatus
      raise
    rescue StandardError, NotImplementedError => e
      outage = Kinetix::DatabaseOutage.explains?(e)
      Rails.logger.error(
        "gRPC #{name_of(method)} failed (request_id=#{Kinetix::RequestId.current || '-'}): #{e.class}: #{e.message}"
      )
      Rails.logger.error(e.backtrace&.first(20)&.join("\n").to_s)
      raise outage ? GRPC::Unavailable.new(UNAVAILABLE_DETAIL) : GRPC::Internal.new(INTERNAL_DETAIL)
    end

    sig { params(method: T.untyped).returns(String) }
    def name_of(method)
      "#{method.receiver.class.name}##{method.name}"
    rescue StandardError
      "-"
    end
  end
end
