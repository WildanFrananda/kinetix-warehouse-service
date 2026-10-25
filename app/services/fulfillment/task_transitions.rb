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

    PROGRESS = T.let(%w[received packing packed].freeze, T::Array[String])

    sig { params(from: String, to: String).returns(T::Boolean) }
    def self.merchant_may?(from:, to:)
      MERCHANT_MOVES.fetch(from, []).include?(to)
    end

    sig { params(status: String).returns(T::Boolean) }
    def self.scannable?(status)
      PROGRESS.include?(status)
    end

    sig { params(from: String, lines_remaining: Integer).returns(T::Array[String]) }
    def self.steps_on_scan(from:, lines_remaining:)
      case from
      when "received" then lines_remaining.zero? ? %w[packing packed] : %w[packing]
      when "packing" then lines_remaining.zero? ? %w[packed] : []
      else []
      end
    end

    sig { params(status: String, step: String).returns(T::Boolean) }
    def self.reached?(status, step)
      at = PROGRESS.index(status)
      wanted = PROGRESS.index(step)
      return false if at.nil? || wanted.nil?

      at >= wanted
    end
  end
end
