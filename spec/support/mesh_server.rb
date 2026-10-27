# typed: false
# frozen_string_literal: true

require "socket"
require "fulfillment/v1/task_services_pb"
require "fulfillment/v1/fulfillment_services_pb"

RSpec.shared_context "warehouse serves gRPC over mTLS" do
  let(:pki) { MeshPki.new }

  around do |example|
    names = %w[KINETIX_PKI_DIR KINETIX_GRPC_ALLOWED_PEERS]
    previous = names.to_h { |name| [ name, ENV.fetch(name, nil) ] }
    ENV["KINETIX_PKI_DIR"] = pki.server_dir
    ENV["KINETIX_GRPC_ALLOWED_PEERS"] = "catalog,order"
    example.run
  ensure
    previous.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    pki.remove
  end

  before do
    started = Queue.new
    allow(Kinetix::Metrics).to receive(:collection).and_return(Kinetix::Metrics::Collection.new)
    allow(Kinetix::Metrics::HttpServer)
      .to receive(:new)
      .and_return(instance_double(Kinetix::Metrics::HttpServer, start: true, stop: nil))
    allow(GRPC::RpcServer).to receive(:new).and_wrap_original do |original, **args|
      original.call(**args).tap { |server| started << server }
    end
    allow_any_instance_of(GRPC::RpcServer)
      .to receive(:run_till_terminated_or_interrupted) { |server, _signals| server.run }

    @port = free_port
    @serving = Thread.new { GrpcServer.run(port: @port) }
    @server = started.pop
    @server.wait_till_running(10)
  end

  after do
    @server&.stop
    @serving&.join(10)
  end

  def free_port
    listener = TCPServer.new("127.0.0.1", 0)
    listener.addr[1]
  ensure
    listener&.close
  end

  def address
    "localhost:#{@port}"
  end

  def tasks(caller = "order")
    Fulfillment::V1::FulfillmentTaskService::Stub.new(address, pki.channel_credentials(caller), timeout: 10)
  end

  def stock(caller = "order")
    Fulfillment::V1::BinStockService::Stub.new(address, pki.channel_credentials(caller), timeout: 10)
  end
end
