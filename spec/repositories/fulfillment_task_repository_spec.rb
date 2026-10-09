# typed: false

require "rails_helper"

RSpec.describe FulfillmentTaskRepository do
  let(:repository) { described_class.new }
  let(:task) { create(:fulfillment_task, status: "received") }

  it "moves a task that is still where the caller saw it" do
    moved = repository.update_status(
      merchant_id: task.merchant_id, task_id: task.id, status: "packing", from: "received"
    )

    expect(moved&.status).to eq("packing")
  end

  it "does not move a task that moved on since the caller read it" do
    repository.update_status(merchant_id: task.merchant_id, task_id: task.id, status: "packing", from: "received")

    second = repository.update_status(
      merchant_id: task.merchant_id, task_id: task.id, status: "packing", from: "received"
    )

    expect(second).to be_nil
    expect(task.reload.status).to eq("packing")
  end

  it "does not move another merchant's task" do
    other = create(:merchant)

    moved = repository.update_status(merchant_id: other.id, task_id: task.id, status: "packing")

    expect(moved).to be_nil
    expect(task.reload.status).to eq("received")
  end
end
