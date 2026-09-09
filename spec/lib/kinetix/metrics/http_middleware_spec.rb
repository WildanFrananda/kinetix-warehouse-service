# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::HttpMiddleware do
  subject(:middleware) do
    described_class.new(app, known_paths: [ "/probe" ], collection: collection)
  end

  let(:collection) { Kinetix::Metrics::Collection.new(mirror: silent_mirror) }
  let(:silent_mirror) { Kinetix::Metrics::Mirror.new(redis: Class.new { def get(_key) = nil }.new) }
  let(:env) { { "REQUEST_METHOD" => "GET", "PATH_INFO" => "/probe" } }
  let(:app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }

  def series_for(status)
    collection.http_requests.samples.find do |sample|
      sample.labels == { "method" => "GET", "route" => "/probe", "status" => status }
    end&.value
  end

  it "counts the status the application answered with" do
    middleware.call(env)

    expect(series_for("200")).to eq(1.0)
  end

  it "counts a 500 and lets the application's exception through" do
    failing = ->(_env) { raise ArgumentError, "the application failed" }

    expect { described_class.new(failing, known_paths: [ "/probe" ], collection: collection).call(env) }
      .to raise_error(ArgumentError, "the application failed")
    expect(series_for("500")).to eq(1.0)
  end

  describe "when recording itself fails" do
    before do
      allow(collection.http_requests).to receive(:increment).and_raise(RuntimeError, "counter is gone")
    end

    it "still returns the response the application produced" do
      expect(middleware.call(env)).to eq([ 200, {}, [ "ok" ] ])
    end

    it "does not invent a 500 for a request that succeeded" do
      middleware.call(env)

      expect(series_for("500")).to be_nil
    end

    it "says so in the log rather than dropping the sample in silence" do
      allow(Rails.logger).to receive(:warn)

      middleware.call(env)

      expect(Rails.logger).to have_received(:warn).with(/dropped an HTTP metric sample.*counter is gone/)
    end

    it "does not fail the request when the logger is unavailable either" do
      allow(Rails).to receive(:logger).and_return(nil)

      expect { middleware.call(env) }.not_to raise_error
    end
  end

  describe "when the response status cannot be read" do
    it "counts it as (unknown) rather than failing a request that was served" do
      malformed = ->(_env) { [ nil, {}, [ "ok" ] ] }
      subject = described_class.new(malformed, known_paths: [ "/probe" ], collection: collection)

      expect(subject.call(env)).to eq([ nil, {}, [ "ok" ] ])
      expect(series_for("(unknown)")).to eq(1.0)
      expect(series_for("500")).to be_nil
    end

    it "survives a response that is not a tuple at all" do
      not_a_tuple = ->(_env) { nil }
      subject = described_class.new(not_a_tuple, known_paths: [ "/probe" ], collection: collection)

      expect(subject.call(env)).to be_nil
      expect(series_for("(unknown)")).to eq(1.0)
    end
  end

  it "still times the request it could not label a status for" do
    malformed = ->(_env) { [ nil, {}, [] ] }
    described_class.new(malformed, known_paths: [ "/probe" ], collection: collection).call(env)

    count = collection.http_request_duration.samples.find do |sample|
      sample.name == "kinetix_http_request_duration_seconds_count" &&
        sample.labels == { "method" => "GET", "route" => "/probe" }
    end

    expect(count&.value).to eq(1.0)
  end
end
