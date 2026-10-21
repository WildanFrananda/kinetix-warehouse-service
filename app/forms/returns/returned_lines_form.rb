# typed: strict

module Returns
  class ReturnedLinesForm
    extend T::Sig

    sig { params(raw: T.untyped).void }
    def initialize(raw)
      @raw = T.let(raw, T.untyped)
    end

    sig { returns(T::Boolean) }
    def well_formed?
      raw = @raw
      return true if raw.nil?
      return false unless raw.is_a?(Array)

      raw.all? { |line| line.is_a?(ActionController::Parameters) }
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def lines
      entries = @raw.is_a?(Array) ? @raw : []

      entries.map do |line|
        { sku: line[:sku].to_s, quantity: Integer(line[:quantity].to_s, exception: false) }
      end
    end

    sig { returns(T.nilable(String)) }
    def problem
      found = lines
      return "Name at least one SKU that came back" if found.empty?
      return "Every line needs a SKU" if found.any? { |line| line[:sku].strip.empty? }
      return "Every line needs a whole quantity of at least 1" unless found.all? { |line| countable?(line[:quantity]) }

      nil
    end

    private

    sig { params(quantity: T.untyped).returns(T::Boolean) }
    def countable?(quantity)
      return false unless quantity.is_a?(Integer)

      quantity >= 1
    end
  end
end
