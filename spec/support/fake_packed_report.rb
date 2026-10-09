# typed: false
# frozen_string_literal: true

class FakePackedReport < Order::GrpcClient
  attr_reader :packed

  def initialize
    super(host: "127.0.0.1:1")
    @packed = []
  end

  def fulfillment_packed(merchant_principal_id:, order_number:, fulfillment_task_id:)
    @packed << order_number
    { success: true, already_packed: false, dispatch_ref: "DISPATCH-1", error: nil }
  end
end
