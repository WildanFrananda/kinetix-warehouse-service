# frozen_string_literal: true

require "rails_helper"

RSpec.describe "GET /metrics", type: :request do
  LABEL_VALUES = /[a-z_]+="[^"]*"/
  LEAKED_IDENTIFIER = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}|[0-9a-f]{24,}|@[a-z0-9.-]+\.[a-z]{2,}/i
  UNTEMPLATED_ROUTE = %r{route="[^"]*/[0-9]+}

  def scrape
    get "/metrics"
    response.body
  end

  it "answers unauthenticated, in Prometheus text format" do
    body = scrape

    expect(response).to have_http_status(:ok)
    expect(response.headers["content-type"]).to start_with("text/plain; version=0.0.4")
    expect(body).to match(/^# HELP /)
    expect(body).to match(/^# TYPE /)
  end

  it "asks not to be cached" do
    scrape

    expect(response.headers["cache-control"]).to eq("no-store")
  end

  it "names the metrics the contract requires of every service" do
    body = scrape

    expect(body).to match(/^kinetix_http_requests_total/)
    expect(body).to match(/^kinetix_http_request_duration_seconds/)
    expect(body).to match(/^kinetix_build_info/)
  end

  it "names the gRPC calls it makes to other services, at zero before it makes any" do
    body = scrape

    expect(body).to match(/^kinetix_grpc_client_calls_total/)
    expect(body).to include(
      'kinetix_grpc_client_calls_total{peer="identity",' \
      'grpc_method="/identity.v1.IdentityService/GetUserProfile",grpc_code="OK"}'
    )
    expect(body).to include('peer="matching"')
  end

  it "names itself and its version on kinetix_build_info" do
    line = scrape.lines.find { |l| l.start_with?("kinetix_build_info") }

    expect(line).to match(/service="[^"]+"/)
    expect(line).to match(/version="[^"]+"/)
  end

  describe "the route label" do
    it "is the template the router matched, not the path the client sent" do
      get "/orders/42/label_view"
      body = scrape

      expect(body).to include('route="/orders/{id}/label_view"')
      expect(body).not_to include("/orders/42/label_view")
    end

    it "is one bounded value for everything that matched no route" do
      get "/definitely/not/a/route/91"
      body = scrape

      expect(body).to include('route="(unmatched)"')
      expect(body).not_to include("/definitely/not/a/route")
    end

    it "never carries a number where a template belongs" do
      get "/orders/42/label_view"
      get "/api/v1/orders/7/status"

      expect(scrape.scan(UNTEMPLATED_ROUTE)).to be_empty
    end
  end

  describe "what must never reach a label" do
    it "carries no correlation id, even though every request has one" do
      id = "kinetix-spec-8f3a2b1c-4d5e-6f70-b1c2-d3e4f5a6b7c8"
      get "/health", headers: { "X-Request-Id" => id }

      expect(scrape).not_to include(id)
    end

    it "carries no identifier in any label value" do
      get "/orders/8f3a2b1cd4e56f70b1c2d3e4f5a6b7c8/label_view"
      get "/tracking/ORD-9F2A1B/stream"

      leaked = scrape.scan(LABEL_VALUES).grep(LEAKED_IDENTIFIER)

      expect(leaked).to be_empty
    end
  end

  describe "the gRPC calls this process does not serve" do
    it "withholds the counter rather than reporting zero of them" do
      body = scrape

      expect(body).not_to include("kinetix_grpc_server_calls_total")
      expect(body).to include("kinetix_metrics_mirror_up 0")
    end
  end
end
