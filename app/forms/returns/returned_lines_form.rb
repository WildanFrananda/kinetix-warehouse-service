# typed: strict

module Returns
  class ReturnedLinesForm
    extend T::Sig

    QUANTITIES = T.let(1..Kinetix::IntegerParam::MAX_INT32, T::Range[Integer])
    QUANTITY_PROBLEM = T.let(
      "Every line needs a whole quantity from 1 to #{QUANTITIES.end}, written in digits",
      String
    )

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
        { sku: line[:sku], quantity: Kinetix::IntegerParam.parse(line[:quantity], signed: false) }
      end
    end

    sig { returns(T.nilable(String)) }
    def problem
      found = lines
      return "Name at least one SKU that came back" if found.empty?
      return "Every line needs a SKU, written as a string" unless found.all? { |line| named?(line[:sku]) }
      return QUANTITY_PROBLEM unless found.all? { |line| countable?(line[:quantity]) }

      nil
    end

    private

    sig { params(sku: T.untyped).returns(T::Boolean) }
    def named?(sku)
      return false unless sku.is_a?(String)

      !sku.strip.empty? && !sku.include?("\u0000")
    end

    sig { params(quantity: T.untyped).returns(T::Boolean) }
    def countable?(quantity)
      return false unless quantity.is_a?(Integer)

      QUANTITIES.cover?(quantity)
    end
  end
end
