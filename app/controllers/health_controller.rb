# typed: strict

class HealthController < ApplicationController
  extend T::Sig

  sig { void }
  def show
    render json: { status: "ok", service: "kinetix-warehouse-service" }
  end

  sig { void }
  def ready
    ActiveRecord::Base.connection.execute("SELECT 1")
    render json: { status: "ok", database: "reachable" }
  rescue StandardError => e
    Rails.logger.error("readiness check failed: #{e.class}: #{e.message}")
    render json: { status: "unavailable", database: "unreachable" }, status: :service_unavailable
  end
end
