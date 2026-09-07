# typed: strict
# frozen_string_literal: true

module Kinetix
  module RequestId
    extend T::Sig

    HEADER = "x-request-id"

    KEY = :kinetix_request_id

    sig { returns(T.nilable(String)) }
    def self.current
      Thread.current[KEY]
    end

    sig do
      type_parameters(:R)
        .params(id: T.nilable(String), blk: T.proc.returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def self.with(id, &blk)
      previous = Thread.current[KEY]
      Thread.current[KEY] = id.presence
      yield
    ensure
      Thread.current[KEY] = previous
    end

    sig { returns(T::Hash[String, String]) }
    def self.metadata
      id = current
      id.nil? ? {} : { HEADER => id }
    end
  end
end
