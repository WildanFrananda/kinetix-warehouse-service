# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"
require_relative "proto_nul"
require_relative "request_id"

module Kinetix
  class NulRefusalInterceptor < GRPC::ServerInterceptor
    extend T::Sig

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def request_response(request:, call:, method:, &blk)
      refuse_nul!(request)
      yield
    end

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def server_streamer(request:, call:, method:, &blk)
      refuse_nul!(request)
      yield
    end

    private

    sig { params(request: T.untyped).void }
    def refuse_nul!(request)
      field = Kinetix::ProtoNul.field(request)
      return if field.nil?

      Rails.logger.warn(
        "refused a gRPC #{request.class.name}: #{field} carries a NUL character " \
        "(request_id=#{Kinetix::RequestId.current || '-'})"
      )
      raise GRPC::InvalidArgument.new("#{field} must not contain a NUL character")
    end
  end
end
