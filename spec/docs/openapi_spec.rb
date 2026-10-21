# typed: false

require "rails_helper"
require "yaml"

RSpec.describe "docs/openapi.yaml" do
  let(:document) { YAML.safe_load_file(Rails.root.join("docs/openapi.yaml")) }

  let(:documented) do
    document.fetch("paths").flat_map do |path, operations|
      operations.keys.map { |verb| "#{verb.upcase} #{path}" }
    end
  end

  let(:served) do
    Rails.application.routes.routes.filter_map do |route|
      verb = route.verb.to_s
      next if verb.empty?

      path = route.path.spec.to_s.delete_suffix("(.:format)")
      next unless path.start_with?("/api/v1/")

      "#{verb} #{path.delete_prefix('/api/v1').gsub(/:(\w+)/, '{\1}')}"
    end
  end

  it "documents exactly the API routes this service serves" do
    expect(documented).to match_array(served)
  end

  it "is served under the gateway's prefix, which the gateway strips to /api/v1" do
    expect(document.fetch("servers").map { |server| server.fetch("url") }).to all(end_with("/api/v1/warehouse"))
  end
end
