# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_pb"

module Inventory
  class StepOutcome < T::Struct
    const :message, T.any(
      Fulfillment::V1::ReserveStockResponse,
      Fulfillment::V1::ReleaseStockResponse
    )
    const :commit, T::Boolean
    const :applied, T::Boolean, default: false
  end
end
