# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::JsonLogFormatter do
  subject(:formatter) { described_class.new(source: "grpc_server") }

  let(:at) { Time.utc(2026, 9, 9, 12, 30, 15, 250_000) }

  def parse(line)
    JSON.parse(line)
  end

  it "writes one JSON object on one line" do
    line = formatter.call("INFO", at, nil, "reserved 3 units")

    expect(line).to end_with("\n")
    expect(line.count("\n")).to eq(1)
    expect(parse(line)).to include("level" => "INFO", "message" => "reserved 3 units")
  end

  it "stamps the timestamp in UTC with milliseconds" do
    expect(parse(formatter.call("INFO", at, nil, "x"))["timestamp"]).to eq("2026-09-09T12:30:15.250Z")
  end

  it "names the source when the caller supplied no progname" do
    expect(parse(formatter.call("INFO", at, nil, "x"))["logger"]).to eq("grpc_server")
    expect(parse(formatter.call("INFO", at, "ActiveRecord", "x"))["logger"]).to eq("ActiveRecord")
  end

  describe "the correlation id" do
    it "reaches the line raw, so a plain grep for it still matches" do
      id = "kinetix-trace-1757000000-4242"

      line = Kinetix::RequestId.with(id) { formatter.call("INFO", at, nil, "gRPC ReserveStock") }

      expect(line).to include(id)
      expect(parse(line)["request_id"]).to eq(id)
    end

    it "reads the thread-local the middleware and the interceptor already fill in" do
      expect(parse(formatter.call("INFO", at, nil, "x"))["request_id"]).to be_nil
    end
  end

  it "keeps a multi-line message on one line" do
    line = formatter.call("ERROR", at, nil, "boom\n  app/models/order.rb:12\n  app/x.rb:3")

    expect(line.count("\n")).to eq(1)
    expect(parse(line)["message"]).to eq("boom\n  app/models/order.rb:12\n  app/x.rb:3")
  end

  it "renders an exception rather than inspecting it" do
    entry = parse(formatter.call("ERROR", at, nil, ArgumentError.new("no sku")))

    expect(entry["message"]).to eq("ArgumentError: no sku")
  end

  it "survives a message that is not valid in its own encoding" do
    entry = parse(formatter.call("WARN", at, nil, "sku \xC3(".dup.force_encoding("UTF-8")))

    expect(entry["message"]).to include("sku")
  end
end
