# typed: strict
# frozen_string_literal: true

module Kinetix
  module PrincipalId
    extend T::Sig

    FORMAT = T.let(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, Regexp)

    sig { params(text: String).returns(T.nilable(String)) }
    def self.canonical(text)
      candidate = text.strip
      return nil unless FORMAT.match?(candidate)

      candidate.downcase
    end
  end
end
