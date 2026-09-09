# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::Mirror do
  let(:store) do
    Class.new do
      attr_accessor :value, :failure

      def get(_key)
        raise failure if failure

        value
      end

      def set(_key, value)
        raise failure if failure

        @value = value
      end
    end.new
  end

  let(:mirror) { described_class.new(redis: store, key: "spec:mirror") }
  let(:label_names) { %w[grpc_method grpc_code] }

  let(:counter) do
    Kinetix::Metrics::Counter.new(
      name: "kinetix_grpc_server_calls_total",
      help: "served calls",
      label_names: label_names
    )
  end

  it "carries the whole table from one process to the other" do
    counter.increment("grpc_method" => "/fulfillment.v1.FulfillmentService/CreateOrder", "grpc_code" => "OK")
    counter.increment("grpc_method" => "/fulfillment.v1.FulfillmentService/CreateOrder", "grpc_code" => "OK")
    counter.initialize_series("grpc_method" => "/grpc.health.v1.Health/Check", "grpc_code" => "OK")

    mirror.publish(counter)
    samples = mirror.read(label_names)

    expect(samples.map { |s| [ s.labels, s.value ] }).to contain_exactly(
      [ { "grpc_method" => "/fulfillment.v1.FulfillmentService/CreateOrder", "grpc_code" => "OK" }, 2.0 ],
      [ { "grpc_method" => "/grpc.health.v1.Health/Check", "grpc_code" => "OK" }, 0.0 ]
    )
  end

  describe "when it cannot tell" do
    it "reads nothing when nothing was ever published" do
      expect(mirror.read(label_names)).to be_nil
    end

    it "reads nothing when the publication is older than the freshness window" do
      mirror.publish(counter)
      travel_to(Time.current + described_class::MAX_AGE_SECONDS + 1) do
        expect(mirror.read(label_names)).to be_nil
      end
    end

    it "reads nothing when the publication is labelled differently from what was asked for" do
      mirror.publish(counter)

      expect(mirror.read(%w[grpc_method grpc_code peer])).to be_nil
    end

    it "reads nothing when the payload is not JSON" do
      store.value = "not json"

      expect(mirror.read(label_names)).to be_nil
    end

    it "lets a store failure out, so the caller decides what to say about it" do
      store.failure = RuntimeError.new("connection refused")

      expect { mirror.read(label_names) }.to raise_error(RuntimeError, "connection refused")
    end
  end
end
