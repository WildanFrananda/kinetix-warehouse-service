# typed: false
# frozen_string_literal: true

require "rails_helper"
require "google/protobuf/wrappers_pb"
require "google/protobuf/struct_pb"
require "fulfillment/v1/task_services_pb"

RSpec.describe Kinetix::ProtoNul do
  def message(name)
    Google::Protobuf::DescriptorPool.generated_pool.lookup(name).msgclass
  end

  it "names no field when no string carries a NUL" do
    request = Fulfillment::V1::CreateFulfillmentTaskRequest.new(
      merchant_principal_id: "p",
      order_number: "ORD-1",
      lines: [ Fulfillment::V1::FulfillmentTaskLine.new(sku: "S", quantity: 1) ]
    )

    expect(described_class.field(request)).to be_nil
  end

  it "names a top-level string field" do
    expect(described_class.field(message("google.protobuf.StringValue").new(value: "a\u0000b"))).to eq("value")
  end

  it "names a string inside a repeated message by its path" do
    request = Fulfillment::V1::CreateFulfillmentTaskRequest.new(
      lines: [
        Fulfillment::V1::FulfillmentTaskLine.new(sku: "S"),
        Fulfillment::V1::FulfillmentTaskLine.new(sku: "\u0000")
      ]
    )

    expect(described_class.field(request)).to eq("lines.sku")
  end

  it "names a map whose key or whose value carries one" do
    struct = message("google.protobuf.Struct")
    value = message("google.protobuf.Value")
    keyed = struct.new(fields: { "k\u0000" => value.new(string_value: "v") })
    valued = struct.new(fields: { "k" => value.new(string_value: "v\u0000") })

    expect(described_class.field(keyed)).to eq("fields")
    expect(described_class.field(valued)).to eq("fields.string_value")
  end

  it "leaves bytes alone, where a zero byte is data" do
    expect(described_class.field(message("google.protobuf.BytesValue").new(value: "\x00\x01".b))).to be_nil
  end
end
