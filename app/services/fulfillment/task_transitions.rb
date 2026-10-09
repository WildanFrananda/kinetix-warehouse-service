# typed: strict

module Fulfillment
  class TaskTransitions
    extend T::Sig

    MERCHANT_MOVES = T.let(
      {
        "received" => %w[packing].freeze,
        "packing" => %w[packed].freeze,
        "packed" => %w[packed].freeze
      }.freeze,
      T::Hash[String, T::Array[String]]
    )

    NEXT_ON_SCAN = T.let(
      {
        "received" => "packing",
        "packing" => "packed",
        "packed" => "packed"
      }.freeze,
      T::Hash[String, String]
    )

    sig { params(from: String, to: String).returns(T::Boolean) }
    def self.merchant_may?(from:, to:)
      MERCHANT_MOVES.fetch(from, []).include?(to)
    end

    sig { params(from: String).returns(T.nilable(String)) }
    def self.next_on_scan(from)
      NEXT_ON_SCAN[from]
    end
  end
end
