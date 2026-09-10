# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::Collection do
  let(:collection) { described_class.new(version: "1.2.3") }

  describe "a process that has served nothing yet" do
    it "already names the metrics the contract requires of every service" do
      body = scrape_with(nil)

      expect(body).to match(/^kinetix_http_requests_total/)
      expect(body).to match(/^kinetix_http_request_duration_seconds/)
      expect(body).to match(/^kinetix_build_info/)
    end

    it "reports the scrape route it really serves, at the zero it has really counted" do
      body = scrape_with(nil)

      expect(body).to include('kinetix_http_requests_total{method="GET",route="/metrics",status="200"} 0')
      expect(body).to include('kinetix_http_request_duration_seconds_count{method="GET",route="/metrics"} 0')
      expect(body).to include('kinetix_http_request_duration_seconds_sum{method="GET",route="/metrics"} 0')
    end

    it "seeds a floor, not a reset: a request already counted survives" do
      collection.http_requests.increment("method" => "GET", "route" => "/metrics", "status" => "200")
      collection.http_request_duration.observe({ "method" => "GET", "route" => "/metrics" }, 0.01)

      body = scrape_with(nil)

      expect(body).to include('kinetix_http_requests_total{method="GET",route="/metrics",status="200"} 1')
      expect(body).to include('kinetix_http_request_duration_seconds_count{method="GET",route="/metrics"} 1')
    end

    it "seeds nothing but the scrape, so no route it has not served is claimed" do
      routes = scrape_with(nil).scan(/^kinetix_http_requests_total\{[^}]*route="([^"]*)"/).flatten

      expect(routes).to eq([ "/metrics" ])
    end
  end

  it "names itself and its version on kinetix_build_info, and nowhere else" do
    body = scrape_with(nil)

    expect(body).to include('kinetix_build_info{service="kinetix-warehouse-service",version="1.2.3"} 1')
    expect(body.scan(/^kinetix_(?!build_info)\w+\{[^}]*service=/)).to be_empty
  end

  describe "the gRPC counter, which belongs to the process that answers gRPC" do
    it "is absent from a process that answers no gRPC call" do
      expect(scrape_with(nil)).not_to include("kinetix_grpc_server_calls_total")
    end

    it "is served, and counted, by the process that declares itself the gRPC server" do
      counter = collection.serve_grpc_server_calls
      counter.increment("grpc_method" => "/grpc.health.v1.Health/Check", "grpc_code" => "OK")

      expect(collection.scrape).to include(
        'kinetix_grpc_server_calls_total{grpc_method="/grpc.health.v1.Health/Check",grpc_code="OK"} 1'
      )
    end

    it "carries no mirror gauge: nothing is mirrored any more" do
      collection.serve_grpc_server_calls

      expect(collection.scrape).not_to include("kinetix_metrics_mirror_up")
      expect(scrape_with(nil)).not_to include("kinetix_metrics_mirror_up")
    end
  end

  it "exposes a histogram with buckets, a sum and a count, in seconds" do
    collection.http_request_duration.observe({ "method" => "GET", "route" => "/health" }, 0.02)
    body = scrape_with(nil)

    expect(body).to include("# TYPE kinetix_http_request_duration_seconds histogram")
    expect(body).to match(/^kinetix_http_request_duration_seconds_bucket\{.*le="\+Inf"\} 1$/)
    expect(body).to match(/^kinetix_http_request_duration_seconds_sum\{/)
    expect(body).to match(/^kinetix_http_request_duration_seconds_count\{/)
  end

  def scrape_with(_unused)
    collection.scrape
  end
end
