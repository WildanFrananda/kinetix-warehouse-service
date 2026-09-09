# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::GrpcServerInterceptor do
  subject(:interceptor) { described_class.new(counter) }

  let(:counter) do
    Kinetix::Metrics::Counter.new(
      name: "kinetix_grpc_server_calls_total",
      help: "served calls",
      label_names: %w[grpc_method grpc_code]
    )
  end

  let(:handler) { Rpc::HealthHandler.new }
  let(:health_check) { handler.method(:check) }

  def value_for(grpc_method, grpc_code)
    counter.samples
           .find { |s| s.labels == { "grpc_method" => grpc_method, "grpc_code" => grpc_code } }
           &.value
  end

  it "labels a call with the wire name the proto declares" do
    interceptor.request_response(request: nil, call: nil, method: health_check) { :served }

    expect(value_for("/grpc.health.v1.Health/Check", "OK")).to eq(1.0)
  end

  it "records the status code of a call the handler rejected, and re-raises" do
    expect do
      interceptor.request_response(request: nil, call: nil, method: health_check) do
        raise GRPC::PermissionDenied, "caller is not on the allow list"
      end
    end.to raise_error(GRPC::PermissionDenied)

    expect(value_for("/grpc.health.v1.Health/Check", "PERMISSION_DENIED")).to eq(1.0)
  end

  it "records anything else as the UNKNOWN gRPC turns it into on the wire" do
    expect do
      interceptor.request_response(request: nil, call: nil, method: health_check) { raise "boom" }
    end.to raise_error(RuntimeError)

    expect(value_for("/grpc.health.v1.Health/Check", "UNKNOWN")).to eq(1.0)
  end

  it "returns what the handler returned" do
    result = interceptor.request_response(request: nil, call: nil, method: health_check) { :served }

    expect(result).to eq(:served)
  end

  describe "#declare" do
    it "starts every RPC the handler serves at zero" do
      interceptor.declare(handler)

      expect(value_for("/grpc.health.v1.Health/Check", "OK")).to eq(0.0)
      expect(value_for("/grpc.health.v1.Health/Watch", "OK")).to eq(0.0)
    end

    it "does not lose the counts a call already made" do
      interceptor.request_response(request: nil, call: nil, method: health_check) { :served }
      interceptor.declare(handler)

      expect(value_for("/grpc.health.v1.Health/Check", "OK")).to eq(1.0)
    end
  end
end
