# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "TrackingStreamController SSE", type: :request do
  describe "GET /tracking/:order_number/stream" do
    it "returns text/event-stream headers for buyer live tracking" do
      get tracking_stream_path(order_number: "ORD-TEST-123")

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to eq("text/event-stream")
      expect(response.headers["Cache-Control"]).to eq("no-cache")
      expect(response.body).to include("event: connected")
      expect(response.body).to include("driver_location")
    end
  end
end
