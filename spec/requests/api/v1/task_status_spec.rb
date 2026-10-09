# typed: false

require "rails_helper"

RSpec.describe "Api::V1::FulfillmentTasks status changes", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-3333-4444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let(:headers) { bearer(access_token(principal_id: principal_id)) }
  let(:order) { FakePackedReport.new }

  before do
    allow(Container).to receive(:[]).and_call_original
    allow(Container).to receive(:[]).with(:order_grpc_client).and_return(order)
  end

  def move(task, to)
    patch "/api/v1/fulfillment_tasks/#{task.id}/status", params: { status: to }, headers: headers
  end

  def scan(task, code)
    post "/api/v1/fulfillment_tasks/#{task.id}/verify_scan", params: { scanned_code: code }, headers: headers
  end

  describe "moving a task by hand" do
    it "goes forward one step at a time, and tells order once it is packed" do
      task = create(:fulfillment_task, merchant: merchant, status: "received")

      move(task, "packing")
      expect(response).to have_http_status(:ok)
      move(task, "packed")
      expect(response).to have_http_status(:ok)

      expect(task.reload.status).to eq("packed")
      expect(order.packed).to eq([ task.order_number ])
    end

    it "lets a packed task be reported again, for when order did not hear it the first time" do
      task = create(:fulfillment_task, merchant: merchant, status: "packed")

      move(task, "packed")

      expect(response).to have_http_status(:ok)
      expect(order.packed).to eq([ task.order_number ])
    end

    it "will not skip packing" do
      task = create(:fulfillment_task, merchant: merchant, status: "received")

      move(task, "packed")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.status).to eq("received")
      expect(order.packed).to be_empty
    end

    it "will not bring a task order cancelled back to life" do
      task = create(:fulfillment_task, merchant: merchant, status: "cancelled")

      move(task, "packed")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.status).to eq("cancelled")
      expect(order.packed).to be_empty, "a refunded order must not be sent a courier"
    end

    it "will not let a merchant cancel a task; that is order's to do" do
      task = create(:fulfillment_task, merchant: merchant, status: "received")

      move(task, "cancelled")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.status).to eq("received")
    end

    it "will not move a task backwards" do
      task = create(:fulfillment_task, merchant: merchant, status: "packed")

      move(task, "received")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.status).to eq("packed")
    end
  end

  describe "moving a task by scanning it" do
    it "will not scan a cancelled task back into packing" do
      task = create(:fulfillment_task, merchant: merchant, status: "cancelled")
      create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M")

      scan(task, "GAMIS-RED-M")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.status).to eq("cancelled")
    end
  end
end
