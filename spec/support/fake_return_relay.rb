# typed: false
# frozen_string_literal: true

class FakeReturnRelay
  include Order::ReturnRelay

  attr_reader :opened, :received

  def initialize
    @opened = []
    @received = []
    @open_error = nil
  end

  def refuse_open(message)
    @open_error = message
  end

  def open_return(merchant_principal_id:, order_number:, reason:)
    if @open_error
      return { success: false, return_number: "", already_open: false, error: @open_error }
    end

    @opened << {
      merchant_principal_id: merchant_principal_id,
      order_number: order_number,
      reason: reason
    }

    { success: true, return_number: "RMA-20260921-ABCD1234", already_open: false, error: nil }
  end

  def return_goods_received(merchant_principal_id:, return_number:, lines:, bin_code:, received_at:)
    @received << {
      merchant_principal_id: merchant_principal_id,
      return_number: return_number,
      lines: lines,
      bin_code: bin_code,
      received_at: received_at
    }

    { accepted: true, already_recorded: false, error: nil }
  end
end
