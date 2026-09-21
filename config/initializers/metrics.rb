# typed: false

require_relative "../../lib/kinetix/metrics"
require_relative "../../lib/kinetix/metrics/grpc_client_recorder"

Rails.application.config.to_prepare do
  [
    [ Order::GrpcClient::PEER, Order::GrpcClient::GRPC_METHOD ],
    [ Order::GrpcClient::PEER, Order::GrpcClient::OPEN_RETURN_METHOD ],
    [ Order::GrpcClient::PEER, Order::GrpcClient::RETURN_GOODS_METHOD ],
    [ Identity::GrpcClient::PEER, Identity::GrpcClient::GRPC_METHOD ]
  ].each do |peer, grpc_method|
    Kinetix::Metrics::GrpcClientRecorder.declare(peer: peer, grpc_method: grpc_method)
  end
end
