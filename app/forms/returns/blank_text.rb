# typed: strict

module Returns
  module BlankText
    extend T::Sig

    PATTERN = T.let(/\A[[:space:]]*\z/, Regexp)

    sig { params(text: String).returns(T::Boolean) }
    def self.blank?(text)
      PATTERN.match?(text)
    end
  end
end
