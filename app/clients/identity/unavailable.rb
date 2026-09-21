# typed: strict
# frozen_string_literal: true

module Identity
  class Unavailable < StandardError
    extend T::Sig

    sig { params(principal_id: String, detail: String).void }
    def initialize(principal_id, detail)
      @principal_id = T.let(principal_id, String)
      super("identity did not answer about principal #{principal_id}: #{detail}")
    end

    sig { returns(String) }
    attr_reader :principal_id
  end
end
