# typed: strict
# frozen_string_literal: true

require "grpc"
require "grpc_reflection"
require_relative "kinetix/service_identity"
require_relative "kinetix/peer_authorization_interceptor"
require_relative "kinetix/request_id_interceptor"
require_relative "kinetix/metrics"
require "fulfillment/v1/fulfillment_services_pb"

class GrpcServer
  extend T::Sig

  DEFAULT_DRAIN_SECONDS = 20.0
  WORKER_EXIT_SECONDS = 2.0

  sig { params(port: Integer).void }
  def self.run(port: Integer(ENV.fetch("GRPC_PORT")))
    identity = Kinetix::ServiceIdentity.new
    metrics = Kinetix::Metrics.collection
    grpc_calls = metrics.serve_grpc_server_calls
    metrics_interceptor = Kinetix::Metrics::GrpcServerInterceptor.new(grpc_calls)

    server = GRPC::RpcServer.new(
      poll_period: drain_seconds,
      pool_keep_alive: WORKER_EXIT_SECONDS,
      interceptors: [
        metrics_interceptor,
        Kinetix::RequestIdInterceptor.new,
        Kinetix::PeerAuthorizationInterceptor.new
      ]
    )
    server.add_http2_port("0.0.0.0:#{port}", identity.server_credentials)

    handlers = [
      Rpc::FulfillmentServiceHandler.new,
      Rpc::BinStockServiceHandler.new,
      Rpc::HealthHandler.new,
      GrpcReflection::Server,
      GrpcReflection::ServerAlpha
    ]
    handlers.each do |handler|
      server.handle(handler)
      metrics_interceptor.declare(handler)
    end

    publisher = Kinetix::Metrics::MirrorPublisher.new(
      mirror: Kinetix::Metrics::Mirror.new,
      counter: grpc_calls
    )
    publisher.start

    metrics_endpoint = Kinetix::Metrics::HttpServer.new(collection: metrics)
    metrics_endpoint.start

    Rails.logger.info("gRPC server listening on 0.0.0.0:#{port} (mTLS)")
    server.run_till_terminated_or_interrupted([ "INT", "TERM" ])
  ensure
    publisher&.stop
    metrics_endpoint&.stop
    Rails.logger.info("gRPC server stopped")
  end

  sig { returns(Float) }
  def self.drain_seconds
    Float(ENV.fetch("KINETIX_DRAIN_SECONDS", DEFAULT_DRAIN_SECONDS.to_s))
  end
end
