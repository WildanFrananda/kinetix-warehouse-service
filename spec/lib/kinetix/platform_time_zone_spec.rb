# typed: false

require "rails_helper"

RSpec.describe Kinetix::PlatformTimeZone do
  it "takes the zone from KINETIX_TIME_ZONE" do
    expect(described_class.from_env({ "KINETIX_TIME_ZONE" => "Asia/Jakarta" }))
      .to eq(ActiveSupport::TimeZone["Asia/Jakarta"])
  end

  it "refuses to start without one" do
    expect { described_class.from_env({}) }.to raise_error(/KINETIX_TIME_ZONE is required/)
  end

  it "refuses to start with a zone nobody has heard of" do
    expect { described_class.from_env({ "KINETIX_TIME_ZONE" => "Mars/Olympus" }) }
      .to raise_error(/KINETIX_TIME_ZONE/)
  end

  it "is what this process was configured with" do
    expect(Rails.configuration.x.platform_time_zone)
      .to eq(ActiveSupport::TimeZone[ENV.fetch("KINETIX_TIME_ZONE")])
  end
end
