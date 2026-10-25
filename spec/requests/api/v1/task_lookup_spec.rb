# typed: false
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::FulfillmentTasks#index, finding a task by its order number", type: :request do
  include_context "identity issues tokens"
  include_context "identity answers about merchants"

  let(:principal_id) { "11111111-2222-4333-8444-555555555555" }
  let!(:merchant) { create(:merchant, principal_id: principal_id) }
  let(:headers) { bearer(access_token(principal_id: principal_id)) }

  def find(order_number, with: headers)
    get "/api/v1/fulfillment_tasks", params: { order_number: order_number }, headers: with
  end

  describe "a task that has left the queue" do
    let!(:task) do
      create(:fulfillment_task, merchant: merchant, order_number: "ORD-SHIPPED-1", status: "packed")
    end

    before do
      create(:fulfillment_task_line, fulfillment_task: task, sku: "GAMIS-RED-M", quantity: 2)
      create(
        :shipping_label,
        fulfillment_task: task,
        awb_number: "KNX-20261022-SHIP0001",
        reprint_count: 0,
        print_count: 1
      )
    end

    it "is found, so a return can be opened for it" do
      get "/api/v1/fulfillment_tasks/queue", headers: headers
      expect(response.parsed_body).to be_empty

      find("ORD-SHIPPED-1")

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.size).to eq(1)
      expect(body.first).to include(
        "id" => task.id,
        "order_number" => "ORD-SHIPPED-1",
        "status" => "packed",
        "tracking_number" => "KNX-20261022-SHIP0001",
        "label_print_count" => 1
      )
      expect(body.first["lines"]).to eq(
        [ { "sku" => "GAMIS-RED-M", "quantity" => 2, "bin_location" => "", "scanned" => false } ]
      )
    end

    it "takes surrounding spaces off what was typed" do
      find("  ORD-SHIPPED-1 ")

      expect(response.parsed_body.map { |found| found["id"] }).to eq([ task.id ])
    end
  end

  it "finds a cancelled task too, whatever its state" do
    task = create(:fulfillment_task, merchant: merchant, order_number: "ORD-CANCELLED-1", status: "cancelled")

    find("ORD-CANCELLED-1")

    expect(response).to have_http_status(:ok)
    found = response.parsed_body.map { |record| [ record["id"], record["status"] ] }
    expect(found).to eq([ [ task.id, "cancelled" ] ])
    expect(response.parsed_body.first["tracking_number"]).to be_nil
    expect(response.parsed_body.first["label_print_count"]).to eq(0)
  end

  it "answers an empty list when this merchant has no task for that order" do
    find("ORD-NOTHING")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it "does not find another merchant's task for the same order number" do
    create(:fulfillment_task, merchant: create(:merchant), order_number: "ORD-THEIRS-1")

    find("ORD-THEIRS-1")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  describe "what it refuses" do
    it "refuses a request that names no order" do
      get "/api/v1/fulfillment_tasks", headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("order_number")
    end

    it "refuses a blank order number" do
      find("   ")

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a list where one order number belongs" do
      get "/api/v1/fulfillment_tasks?order_number[]=ORD-1&order_number[]=ORD-2", headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a request with no token" do
      find("ORD-1", with: {})

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token that is not a seller's" do
      find("ORD-1", with: bearer(access_token(principal_id: principal_id, role: "customer")))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to eq("NOT_A_SELLER")
    end

    context "when identity cannot be asked" do
      let(:identity_client) { FakeIdentityClient.new(unavailable: true) }

      it "answers 503 and decides nothing" do
        find("ORD-1")

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["error"]).to eq("IDENTITY_UNAVAILABLE")
      end
    end
  end
end
