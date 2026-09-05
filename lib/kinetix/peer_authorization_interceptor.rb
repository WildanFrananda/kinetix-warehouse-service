# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "grpc"
require_relative "spiffe"

module Kinetix
  class PeerAuthorizationInterceptor < GRPC::ServerInterceptor
    extend T::Sig

    sig { void }
    def initialize
      raw = ENV.fetch("KINETIX_GRPC_ALLOWED_PEERS") do
        raise "KINETIX_GRPC_ALLOWED_PEERS is required and has no default."
      end

      @allowed = T.let(raw.split(",").map(&:strip).reject(&:empty?).to_set, T::Set[String])
      raise "KINETIX_GRPC_ALLOWED_PEERS is set but names no services." if @allowed.empty?

      super()
    end

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def request_response(request:, call:, method:, &blk)
      authorize!(call, method)
      yield
    end

    sig { params(call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def client_streamer(call:, method:, &blk)
      authorize!(call, method)
      yield
    end

    sig { params(request: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def server_streamer(request:, call:, method:, &blk)
      authorize!(call, method)
      yield
    end

    sig { params(requests: T.untyped, call: T.untyped, method: T.untyped, blk: T.untyped).returns(T.untyped) }
    def bidi_streamer(requests:, call:, method:, &blk)
      authorize!(call, method)
      yield
    end

    private

    sig { params(call: T.untyped, method: T.untyped).void }
    def authorize!(call, method)
      peer = Kinetix::Spiffe.service_of(call.peer_cert)

      if peer.nil?
        raise GRPC::Unauthenticated.new("a client certificate carrying a SPIFFE identity is required")
      end

      return if @allowed.include?(peer)

      Rails.logger.warn("refused a gRPC call to #{method} from #{peer}, which is not on the allow list")
      raise GRPC::PermissionDenied.new("this service is not permitted to call warehouse")
    end
  end
end
