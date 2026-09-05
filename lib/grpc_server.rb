# typed: strict
# frozen_string_literal: true

require "grpc"
require "grpc_reflection"
require_relative "kinetix/service_identity"
require_relative "kinetix/peer_authorization_interceptor"
require "fulfillment/v1/fulfillment_services_pb"

class GrpcServer
  extend T::Sig

  sig { params(port: Integer).void }
  def self.run(port: Integer(ENV.fetch("GRPC_PORT")))
    identity = Kinetix::ServiceIdentity.new

    server = GRPC::RpcServer.new(interceptors: [ Kinetix::PeerAuthorizationInterceptor.new ])
    server.add_http2_port("0.0.0.0:#{port}", identity.server_credentials)
    server.handle(Rpc::FulfillmentServiceHandler.new)
    server.handle(Rpc::BinStockServiceHandler.new)

    server.handle(Rpc::HealthHandler.new)

    server.handle(GrpcReflection::Server)
    server.handle(GrpcReflection::ServerAlpha)

    Rails.logger.info("gRPC server listening on 0.0.0.0:#{port} (mTLS)")
    server.run_till_terminated_or_interrupted([ 15, "INT", "TERM" ])
  end
end
