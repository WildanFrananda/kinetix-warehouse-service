# typed: strict

class MetricsController < ActionController::Base
  extend T::Sig

  sig { void }
  def show
    body = Kinetix::Metrics.collection.scrape
    response.headers["cache-control"] = "no-store"
    render plain: body, content_type: Kinetix::Metrics::Exposition::CONTENT_TYPE
  rescue StandardError => e
    Rails.logger.error("metrics scrape failed: #{e.class}: #{e.message}")
    render plain: "metrics unavailable\n", status: :internal_server_error
  end
end
