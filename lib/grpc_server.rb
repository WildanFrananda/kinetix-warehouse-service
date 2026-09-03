# typed: strict
# frozen_string_literal: true

require "grpc"
require "grpc_reflection"
require_relative "generated/fulfillment/v1/fulfillment_service_services_pb"
require_relative "generated/fulfillment/v1/bin_stock_service_services_pb"

class GrpcServer
  extend T::Sig

  sig { params(port: Integer).void }
  def self.run(port: Integer(ENV.fetch("GRPC_PORT")))
    server = GRPC::RpcServer.new
    server.add_http2_port("0.0.0.0:#{port}", :this_port_is_insecure)
    server.handle(Rpc::FulfillmentServiceHandler.new)
    server.handle(Rpc::BinStockServiceHandler.new)

    server.handle(Rpc::HealthHandler.new)

    server.handle(GrpcReflection::Server)
    server.handle(GrpcReflection::ServerAlpha)

    Rails.logger.info("gRPC server listening on 0.0.0.0:#{port}")
    server.run_till_terminated_or_interrupted([ 15, "INT", "TERM" ])
  end
end
