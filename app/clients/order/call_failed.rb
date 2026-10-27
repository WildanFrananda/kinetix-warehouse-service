# typed: strict
# frozen_string_literal: true

module Order
  class CallFailed < StandardError
    extend T::Sig

    sig { params(rpc: String, failure: Order::Failure, detail: String).void }
    def initialize(rpc, failure, detail)
      @rpc = T.let(rpc, String)
      @failure = T.let(failure, Order::Failure)
      super("order failed #{rpc} (#{failure.serialize}): #{detail}")
    end

    sig { returns(String) }
    attr_reader :rpc

    sig { returns(Order::Failure) }
    attr_reader :failure
  end
end
