# typed: strict
# frozen_string_literal: true

require "grpc/health/v1/health_services_pb"

module Rpc
  class HealthHandler < Grpc::Health::V1::Health::Service
    extend T::Sig

    sig { params(_request: T.untyped, _call: T.untyped).returns(T.untyped) }
    def check(_request, _call)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SELECT 1")
      end

      Grpc::Health::V1::HealthCheckResponse.new(status: :SERVING)
    rescue StandardError => e
      Rails.logger.error("gRPC health check failed: #{e.message}")
      Grpc::Health::V1::HealthCheckResponse.new(status: :NOT_SERVING)
    end
  end
end
