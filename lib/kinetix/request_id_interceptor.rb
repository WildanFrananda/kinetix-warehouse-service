# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"
require_relative "request_id"

module Kinetix
  class RequestIdInterceptor < GRPC::ServerInterceptor
    extend T::Sig

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def request_response(request:, call:, method:, &blk)
      around(call, method) { yield }
    end

    sig { params(call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def client_streamer(call:, method:, &blk)
      around(call, method) { yield }
    end

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def server_streamer(request:, call:, method:, &blk)
      around(call, method) { yield }
    end

    sig { params(requests: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def bidi_streamer(requests:, call:, method:, &blk)
      around(call, method) { yield }
    end

    private

    sig { params(call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def around(call, method, &blk)
      Kinetix::RequestId.with(id_of(call)) do
        Rails.logger.info("gRPC #{method} (request_id=#{Kinetix::RequestId.current || '-'})")
        yield
      end
    end

    sig { params(call: T.untyped).returns(T.nilable(String)) }
    def id_of(call)
      call.metadata[Kinetix::RequestId::HEADER]
    rescue StandardError
      nil
    end
  end
end
