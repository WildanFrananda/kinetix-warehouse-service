# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "../metrics"

module Kinetix
  module Metrics
    module AdminActions
      extend T::Sig

      BIN_UPSERT = "warehouse.bin_upsert"
      STOCK_RECEIVE = "warehouse.stock_receive"
      STOCK_ADJUST = "warehouse.stock_adjust"
      ALL = T.let([ BIN_UPSERT, STOCK_RECEIVE, STOCK_ADJUST ].freeze, T::Array[String])

      DONE = "done"
      REFUSED = "refused"
      FAILED = "failed"
      OUTCOMES = T.let([ DONE, REFUSED, FAILED ].freeze, T::Array[String])

      sig { void }
      def self.declare
        ALL.each do |action|
          OUTCOMES.each do |outcome|
            Kinetix::Metrics.collection.admin_actions.initialize_series(
              "action" => action,
              "outcome" => outcome
            )
          end
        end
      end

      sig { params(action: String, outcome: String).void }
      def self.record(action:, outcome:)
        Kinetix::Metrics.collection.admin_actions.increment("action" => action, "outcome" => outcome)
      end

      sig { params(status: Integer).returns(String) }
      def self.outcome_for(status)
        return DONE if status.between?(200, 399)
        return REFUSED if status.between?(400, 499)

        FAILED
      end
    end
  end
end
