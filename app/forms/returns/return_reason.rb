# typed: strict

module Returns
  module ReturnReason
    extend T::Sig

    MAX_LENGTH = 500
    OUTSIDE_BASIC_PLANE = "\u{10000}-\u{10FFFF}"

    sig { params(reason: String).returns(T.nilable(String)) }
    def self.problem(reason)
      return "Reason cannot be blank" if BlankText.blank?(reason)
      return "reason must be at most #{MAX_LENGTH} characters" if utf16_length(reason) > MAX_LENGTH

      nil
    end

    sig { params(reason: String).returns(Integer) }
    def self.utf16_length(reason)
      reason.length + reason.count(OUTSIDE_BASIC_PLANE)
    end
    private_class_method :utf16_length
  end
end
