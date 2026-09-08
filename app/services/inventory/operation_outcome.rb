# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_pb"

module Inventory
  class OperationOutcome < T::Struct
    FRESH = :fresh
    REPLAYED = :replayed
    REPLAY_REFUSED = :replay_refused
    REFUSED = :refused
    CONFLICT = :conflict
    RETRY_LATER = :retry_later

    const :message, T.any(
      Fulfillment::V1::ReserveStockResponse,
      Fulfillment::V1::ReleaseStockResponse
    )
    const :status, Symbol
  end
end
