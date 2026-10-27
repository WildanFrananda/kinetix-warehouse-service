# typed: strict
# frozen_string_literal: true

module Order
  class TimedOut < StandardError
    extend T::Sig

    sig { params(rpc: String, detail: String).void }
    def initialize(rpc, detail)
      @rpc = T.let(rpc, String)
      super("order did not answer #{rpc} in time: #{detail}")
    end

    sig { returns(String) }
    attr_reader :rpc
  end
end
