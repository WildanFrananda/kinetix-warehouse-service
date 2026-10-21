# typed: strict
# frozen_string_literal: true

module Order
  class Unavailable < StandardError
    extend T::Sig

    sig { params(rpc: String, detail: String).void }
    def initialize(rpc, detail)
      @rpc = T.let(rpc, String)
      super("order did not answer #{rpc}: #{detail}")
    end

    sig { returns(String) }
    attr_reader :rpc
  end
end
