# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::Metrics::RouteTemplate do
  describe ".normalise" do
    it "keeps the template and drops the format suffix" do
      expect(described_class.normalise("/api/v1/orders/:id/status(.:format)"))
        .to eq("/api/v1/orders/{id}/status")
    end

    it "braces every dynamic segment" do
      expect(described_class.normalise("/tracking/:order_number/stream(.:format)"))
        .to eq("/tracking/{order_number}/stream")
    end

    it "unwraps optional segments rather than leaving their brackets in the label" do
      expect(described_class.normalise("/orders(/:id)(.:format)")).to eq("/orders/{id}")
    end

    it "braces a glob" do
      expect(described_class.normalise("/files/*path(.:format)")).to eq("/files/{path}")
    end

    it "renders the root as a path" do
      expect(described_class.normalise("(.:format)")).to eq("/")
    end
  end

  describe ".for_request" do
    it "asks the router for the pattern it matched" do
      request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/orders/8/label_view"))
      allow(request).to receive(:route_uri_pattern).and_return("/orders/:id/label_view(.:format)")

      expect(described_class.for_request(request)).to eq("/orders/{id}/label_view")
    end

    it "labels a request that matched no route with a single bounded value" do
      request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/nope/8f3a"))

      expect(described_class.for_request(request)).to eq(described_class::UNMATCHED)
    end
  end
end
