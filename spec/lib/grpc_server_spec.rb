# frozen_string_literal: true

require "rails_helper"

RSpec.describe GrpcServer do
  describe ".drain_seconds" do
    around do |example|
      previous = ENV.fetch("KINETIX_DRAIN_SECONDS", nil)
      example.run
    ensure
      previous.nil? ? ENV.delete("KINETIX_DRAIN_SECONDS") : ENV["KINETIX_DRAIN_SECONDS"] = previous
    end

    it "defaults below the container's stop_grace_period" do
      ENV.delete("KINETIX_DRAIN_SECONDS")

      expect(described_class.drain_seconds).to eq(20.0)
      expect(described_class.drain_seconds + described_class::WORKER_EXIT_SECONDS).to be < 30.0
    end

    it "takes the value the environment sets" do
      ENV["KINETIX_DRAIN_SECONDS"] = "7.5"

      expect(described_class.drain_seconds).to eq(7.5)
    end
  end

  describe ".run" do
    around do |example|
      previous = ENV.fetch("KINETIX_GRPC_ALLOWED_PEERS", nil)
      ENV["KINETIX_GRPC_ALLOWED_PEERS"] = "catalog,order"
      example.run
    ensure
      previous.nil? ? ENV.delete("KINETIX_GRPC_ALLOWED_PEERS") : ENV["KINETIX_GRPC_ALLOWED_PEERS"] = previous
    end

    let(:rpc_server) do
      instance_double(
        GRPC::RpcServer,
        add_http2_port: nil,
        handle: nil,
        run_till_terminated_or_interrupted: nil
      )
    end
    let(:publisher) { instance_double(Kinetix::Metrics::MirrorPublisher, start: nil, stop: nil) }
    let(:metrics_endpoint) { instance_double(Kinetix::Metrics::HttpServer, start: true, stop: nil) }

    before do
      allow(Kinetix::Metrics).to receive(:collection).and_return(Kinetix::Metrics::Collection.new)
      allow(GRPC::RpcServer).to receive(:new).and_return(rpc_server)
      allow(Kinetix::Metrics::MirrorPublisher).to receive(:new).and_return(publisher)
      allow(Kinetix::Metrics::HttpServer).to receive(:new).and_return(metrics_endpoint)
    end

    it "gives calls already in flight a deadline, and their threads a little after it" do
      described_class.run(port: 50_051)

      expect(GRPC::RpcServer).to have_received(:new).with(
        hash_including(
          poll_period: described_class.drain_seconds,
          pool_keep_alive: described_class::WORKER_EXIT_SECONDS
        )
      )
    end

    it "counts calls from outside every other interceptor" do
      described_class.run(port: 50_051)

      interceptors = nil
      expect(GRPC::RpcServer).to have_received(:new) { |args| interceptors = args[:interceptors] }
      expect(interceptors.first).to be_a(Kinetix::Metrics::GrpcServerInterceptor)
      expect(interceptors.map(&:class)).to include(Kinetix::PeerAuthorizationInterceptor)
    end

    it "publishes its counters and serves its own /metrics while it runs" do
      described_class.run(port: 50_051)

      expect(publisher).to have_received(:start)
      expect(metrics_endpoint).to have_received(:start)
    end

    it "publishes once more on the way out, so the drain is not lost" do
      described_class.run(port: 50_051)

      expect(publisher).to have_received(:stop)
      expect(metrics_endpoint).to have_received(:stop)
    end

    it "still tears down when the server itself fails" do
      allow(rpc_server).to receive(:run_till_terminated_or_interrupted).and_raise("listener died")

      expect { described_class.run(port: 50_051) }.to raise_error("listener died")
      expect(publisher).to have_received(:stop)
      expect(metrics_endpoint).to have_received(:stop)
    end
  end
end
