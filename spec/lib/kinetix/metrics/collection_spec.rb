# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::Collection do
  let(:store) { Class.new { def get(_key) = nil }.new }
  let(:mirror) { Kinetix::Metrics::Mirror.new(redis: store) }
  let(:collection) { described_class.new(mirror: mirror, version: "1.2.3") }

  it "names itself and its version on kinetix_build_info, and nowhere else" do
    body = scrape_with(nil)

    expect(body).to include('kinetix_build_info{service="kinetix-warehouse-service",version="1.2.3"} 1')
    expect(body.scan(/^kinetix_(?!build_info)\w+\{[^}]*service=/)).to be_empty
  end

  describe "the gRPC calls it did not serve itself" do
    let(:published) do
      [
        Kinetix::Metrics::Sample.new(
          name: "",
          labels: { "grpc_method" => "/grpc.health.v1.Health/Check", "grpc_code" => "OK" },
          value: 41.0
        )
      ]
    end

    it "renders what the gRPC process published" do
      body = scrape_with(published)

      expect(body).to include(
        'kinetix_grpc_server_calls_total{grpc_method="/grpc.health.v1.Health/Check",grpc_code="OK"} 41'
      )
      expect(body).to include("kinetix_metrics_mirror_up 1")
    end

    it "withholds the counter entirely when the publication cannot be read" do
      body = scrape_with(nil)

      expect(body).not_to include("kinetix_grpc_server_calls_total")
      expect(body).to include("kinetix_metrics_mirror_up 0")
    end

    it "withholds it when the store itself fails, and does not let the scrape fail with it" do
      allow(mirror).to receive(:read).and_raise(RuntimeError, "connection refused")

      body = collection.scrape

      expect(body).not_to include("kinetix_grpc_server_calls_total")
      expect(body).to include("kinetix_metrics_mirror_up 0")
    end

    it "stops mirroring once this process is the one serving gRPC" do
      counter = collection.serve_grpc_server_calls
      counter.increment("grpc_method" => "/grpc.health.v1.Health/Check", "grpc_code" => "OK")

      body = collection.scrape

      expect(body).to include(
        'kinetix_grpc_server_calls_total{grpc_method="/grpc.health.v1.Health/Check",grpc_code="OK"} 1'
      )
      expect(body).not_to include("kinetix_metrics_mirror_up")
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

  def scrape_with(samples)
    allow(mirror).to receive(:read).and_return(samples)
    collection.scrape
  end
end
