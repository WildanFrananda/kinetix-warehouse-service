# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ids in a path", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-4333-8444-777777777777" }
  let!(:merchant) { create(:merchant, principal_id: principal_id, cutoff_hour: 14) }
  let!(:task) { create(:fulfillment_task, merchant: merchant, status: "received") }
  let!(:line) { create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M") }
  let!(:label) { create(:shipping_label, fulfillment_task: task, reprint_count: 0) }
  let(:seller) { bearer(access_token(principal_id: principal_id)) }
  let(:order) { FakePackedReport.new }
  let(:relay) { FakeReturnRelay.new }

  def misspellings(id)
    [ "#{id}abc", "#{id}-1", "+#{id}", "%20#{id}", "#{id}%20", "#{id}e0", "#{id}%0A", "-#{id}", "0x#{id.to_s(16)}" ]
  end

  describe "a task's id" do
    before do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(order)
    end

    it "is read with leading zeros as the same task" do
      patch "/api/v1/fulfillment_tasks/0#{task.id}/status", params: { status: "packing" }, headers: seller

      expect(response).to have_http_status(:ok)
      expect(task.reload.status).to eq("packing")
    end

    it "is 404, and moves no task, when its status is set through anything but digits" do
      misspellings(task.id).each do |spelling|
        patch "/api/v1/fulfillment_tasks/#{spelling}/status", params: { status: "packing" }, headers: seller

        expect(response).to have_http_status(:not_found), "#{spelling} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("Fulfillment task not found")
      end

      expect(task.reload.status).to eq("received")
    end

    it "is 404, and prints no label, when the label is printed through anything but digits" do
      misspellings(task.id).each do |spelling|
        post "/api/v1/fulfillment_tasks/#{spelling}/label", headers: seller

        expect(response).to have_http_status(:not_found), "#{spelling} answered #{response.status}"
      end

      expect(label.reload.print_count).to eq(0)
    end

    it "is 404, and scans no line, when it is scanned through anything but digits" do
      misspellings(task.id).each do |spelling|
        post "/api/v1/fulfillment_tasks/#{spelling}/verify_scan",
             params: { scanned_code: "GAMIS-RED-M" },
             headers: seller

        expect(response).to have_http_status(:not_found), "#{spelling} answered #{response.status}"
      end

      expect(task.reload.status).to eq("received")
      expect(line.reload.scanned_at).to be_nil
    end

    it "is 404 for ids no task can have" do
      [ "0", "9223372036854775808" ].each do |spelling|
        patch "/api/v1/fulfillment_tasks/#{spelling}/status", params: { status: "packing" }, headers: seller

        expect(response).to have_http_status(:not_found), "#{spelling} answered #{response.status}"
      end
    end
  end

  describe "a return's task id" do
    before do
      allow(Container).to receive(:[]).with(:order_grpc_client).and_return(relay)
    end

    it "is 404, and opens no return, through anything but digits" do
      misspellings(task.id).each do |spelling|
        post "/api/v1/fulfillment_tasks/#{spelling}/returns", params: { reason: "Wrong size" }, headers: seller

        expect(response).to have_http_status(:not_found), "#{spelling} answered #{response.status}"
        expect(response.parsed_body["error"]).to eq("Fulfillment task not found")
      end

      expect(relay.opened).to be_empty
    end
  end

  describe "a merchant's id" do
    it "is 404, and sets no cutoff, through anything but digits" do
      misspellings(merchant.id).each do |spelling|
        patch "/api/v1/merchants/#{spelling}", params: { cutoff_hour: 9 }, headers: seller

        expect(response).to have_http_status(:not_found), "#{spelling} answered #{response.status}"
      end

      expect(merchant.reload.cutoff_hour).to eq(14)
    end

    it "is still 403 when it is written in digits and is another merchant's" do
      other = create(:merchant, cutoff_hour: 9)

      patch "/api/v1/merchants/#{other.id}", params: { cutoff_hour: 17 }, headers: seller

      expect(response).to have_http_status(:forbidden)
      expect(other.reload.cutoff_hour).to eq(9)
    end
  end
end
