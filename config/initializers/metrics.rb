# typed: false

require_relative "../../lib/kinetix/metrics"
require_relative "../../lib/kinetix/metrics/grpc_client_recorder"

Rails.application.config.to_prepare do
  [ Identity::GrpcClient, FleetPulse::GrpcClient ].each do |client|
    Kinetix::Metrics::GrpcClientRecorder.declare(
      peer: client::PEER,
      grpc_method: client::GRPC_METHOD
    )
  end
end
