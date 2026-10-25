# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::IntegerParam do
  it "takes a JSON integer as it is, leaving its range to the caller" do
    expect(described_class.parse(7, signed: false)).to eq(7)
    expect(described_class.parse(-7, signed: false)).to eq(-7)
    expect(described_class.parse(2**40, signed: true)).to eq(2**40)
  end

  it "reads a string of ASCII digits in base ten, leading zeros included" do
    expect(described_class.parse("42", signed: false)).to eq(42)
    expect(described_class.parse("0010", signed: false)).to eq(10)
    expect(described_class.parse("9999999999", signed: false)).to eq(9_999_999_999)
  end

  it "takes a sign only where the caller allows one" do
    expect(described_class.parse("-3", signed: true)).to eq(-3)
    expect(described_class.parse("+3", signed: true)).to eq(3)
    expect(described_class.parse("-3", signed: false)).to be_nil
    expect(described_class.parse("+3", signed: false)).to be_nil
  end

  [ true, false, nil, 2.0, 2.9, [ 1 ], { "a" => 1 }, "", " 1", "1 ", "1_000", "0x10", "0b1", "1e3", "12abc",
    "١٢", "12345678901", "+-1" ].each do |value|
    it "refuses #{value.inspect}" do
      expect(described_class.parse(value, signed: true)).to be_nil
    end
  end

  describe ".id" do
    it "reads a path id of ASCII digits, leading zeros included" do
      expect(described_class.id("42")).to eq(42)
      expect(described_class.id("042")).to eq(42)
    end

    it "reads ids up to the largest a bigint column holds" do
      expect(described_class.id("9223372036854775807")).to eq(9_223_372_036_854_775_807)
    end

    [ 42, nil, [ "42" ], "", "0", "000", "-1", "+1", "0x10", "1e3", "12abc", "12-1", " 12", "12 ", "12\n", "١٢",
      "１２", "9223372036854775808", "00000000000000000000001" ].each do |value|
      it "names no record with #{value.inspect}" do
        expect(described_class.id(value)).to be_nil
      end
    end
  end
end
