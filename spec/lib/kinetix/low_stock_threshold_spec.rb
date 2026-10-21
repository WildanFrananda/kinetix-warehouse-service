# typed: false

require "rails_helper"

RSpec.describe Kinetix::LowStockThreshold do
  it "takes the threshold from WAREHOUSE_LOW_STOCK_THRESHOLD" do
    expect(described_class.from_env({ "WAREHOUSE_LOW_STOCK_THRESHOLD" => "7" })).to eq(7)
  end

  it "accepts zero, which turns the warning off" do
    expect(described_class.from_env({ "WAREHOUSE_LOW_STOCK_THRESHOLD" => "0" })).to eq(0)
  end

  it "refuses to start without one" do
    expect { described_class.from_env({}) }.to raise_error(/WAREHOUSE_LOW_STOCK_THRESHOLD is required/)
  end

  %w[five -1 2.5].each do |raw|
    it "refuses to start with #{raw.inspect}" do
      expect { described_class.from_env({ "WAREHOUSE_LOW_STOCK_THRESHOLD" => raw }) }
        .to raise_error(/WAREHOUSE_LOW_STOCK_THRESHOLD=#{Regexp.escape(raw)}/)
    end
  end

  it "is what this process was configured with" do
    expect(Rails.configuration.x.low_stock_threshold).to eq(Integer(ENV.fetch("WAREHOUSE_LOW_STOCK_THRESHOLD")))
  end
end
