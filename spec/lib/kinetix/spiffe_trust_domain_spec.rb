# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Spiffe do
  describe "the trust domain this service accepts" do
    it "keeps the domain the estate runs today when the variable is unset" do
      expect(described_class::TRUST_DOMAIN).to eq("kinetix.local")
    end
  end

  describe ".service_in" do
    it "names the service in an id from the configured domain" do
      expect(described_class.service_in("spiffe://kinetix.local/service/order", "kinetix.local"))
        .to eq("order")
    end

    it "can be pointed at another domain without touching this code" do
      expect(described_class.service_in("spiffe://prod.kinetix/service/order", "prod.kinetix"))
        .to eq("order")
    end

    it "names nobody for an id from another trust domain" do
      expect(described_class.service_in("spiffe://prod.kinetix/service/order", "kinetix.local")).to be_nil
      expect(described_class.service_in("spiffe://kinetix.local/service/order", "prod.kinetix")).to be_nil
    end

    it "refuses a domain this one is merely a prefix of" do
      expect(
        described_class.service_in("spiffe://kinetix.local.example.com/service/order", "kinetix.local")
      ).to be_nil
    end

    it "answers nil rather than echoing an id it cannot read" do
      expect(described_class.service_in("spiffe://kinetix.local/agent/x", "kinetix.local")).to be_nil
      expect(described_class.service_in("spiffe://kinetix.local/service/", "kinetix.local")).to be_nil
      expect(described_class.service_in("spiffe://kinetix.local/service/a/b", "kinetix.local")).to be_nil
    end

    it "answers nil for no id at all" do
      expect(described_class.service_in(nil, "kinetix.local")).to be_nil
    end
  end
end
