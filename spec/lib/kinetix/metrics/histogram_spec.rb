# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::Histogram do
  subject(:histogram) do
    described_class.new(
      name: "kinetix_http_request_duration_seconds",
      help: "Time to serve an HTTP request, in seconds.",
      label_names: %w[method route],
      buckets: [ 0.1, 1.0 ]
    )
  end

  let(:labels) { { "method" => "GET", "route" => "/health" } }

  def value_of(name, extra = {})
    histogram.samples.find { |s| s.name == name && s.labels == labels.merge(extra) }&.value
  end

  it "says nothing at all until something is observed" do
    expect(histogram.samples).to be_empty
  end

  it "counts buckets cumulatively" do
    histogram.observe(labels, 0.05)
    histogram.observe(labels, 0.5)

    expect(value_of("kinetix_http_request_duration_seconds_bucket", "le" => "0.1")).to eq(1.0)
    expect(value_of("kinetix_http_request_duration_seconds_bucket", "le" => "1.0")).to eq(2.0)
  end

  it "puts an observation past the last bound in +Inf and nowhere else" do
    histogram.observe(labels, 30.0)

    expect(value_of("kinetix_http_request_duration_seconds_bucket", "le" => "1.0")).to eq(0.0)
    expect(value_of("kinetix_http_request_duration_seconds_bucket", "le" => "+Inf")).to eq(1.0)
    expect(value_of("kinetix_http_request_duration_seconds_count")).to eq(1.0)
  end

  it "sums the observations in seconds" do
    histogram.observe(labels, 0.25)
    histogram.observe(labels, 0.75)

    expect(value_of("kinetix_http_request_duration_seconds_sum")).to eq(1.0)
  end

  it "refuses a label set that is not the one it declared" do
    expect { histogram.observe({ "method" => "GET" }, 0.1) }.to raise_error(ArgumentError, /route/)
  end
end
