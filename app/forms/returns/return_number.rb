# typed: strict

module Returns
  module ReturnNumber
    extend T::Sig

    FORMAT = T.let(/\ARMA-[0-9]{8}-[0-9A-F]{8}\z/, Regexp)

    sig { params(value: T.untyped).returns(T.nilable(String)) }
    def self.read(value)
      return nil unless value.is_a?(String) && FORMAT.match?(value)

      value
    end
  end
end
