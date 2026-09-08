# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_pb"

module Inventory
  class IdempotentOperation
    extend T::Sig

    KEY_CONFLICT = "IDEMPOTENCY_KEY_CONFLICT"
    IN_PROGRESS = "RESERVATION_IN_PROGRESS"
    LEDGER_BUSY = "STOCK_LEDGER_BUSY"
    LOCK_TIMEOUT = "STOCK_LOCK_TIMEOUT"
    RESERVATION_RELEASED = "STOCK_RESERVATION_RELEASED"

    ASSUMED_CALLER_DEADLINE_SECONDS = 5

    MIN_LOCK_TIMEOUT_SECONDS = 1
    MAX_LOCK_TIMEOUT_SECONDS = 120

    DEFAULT_LOCK_TIMEOUT_SECONDS = 15

    @under_deadline_warned = T.let(false, T::Boolean)

    sig { void }
    def self.apply_lock_timeout!
      ApplicationRecord.connection.execute(
        ApplicationRecord.sanitize_sql_array(
          [ "SELECT set_config('lock_timeout', ?, true)", lock_timeout_ms.to_s ]
        )
      )
    end

    sig { returns(Integer) }
    def self.lock_timeout_ms
      seconds = ENV.fetch("WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS", DEFAULT_LOCK_TIMEOUT_SECONDS).to_i
      clamped = seconds.clamp(MIN_LOCK_TIMEOUT_SECONDS, MAX_LOCK_TIMEOUT_SECONDS)
      warn_once_if_under_caller_deadline(clamped)
      clamped * 1_000
    end

    sig { params(seconds: Integer).void }
    def self.warn_once_if_under_caller_deadline(seconds)
      return if seconds >= ASSUMED_CALLER_DEADLINE_SECONDS
      return if @under_deadline_warned

      @under_deadline_warned = true
      Rails.logger.warn(
        "stock.idem lock_timeout_under_deadline seconds=#{seconds} " \
        "assumed_caller_deadline=#{ASSUMED_CALLER_DEADLINE_SECONDS} — a duplicate will now give " \
        "up before its caller does, so warehouse answers RESERVATION_IN_PROGRESS instead of " \
        "finishing the work. Intended only for tests."
      )
    end

    sig do
      params(
        operation: String,
        key: String,
        digest: String,
        merchant: Merchant,
        order_number: String,
        sku: String,
        quantity: Integer
      ).void
    end
    def initialize(operation:, key:, digest:, merchant:, order_number:, sku:, quantity:)
      @operation = operation
      @key = key
      @digest = digest
      @merchant = merchant
      @order_number = order_number
      @sku = sku
      @quantity = quantity
    end

    sig { params(blk: T.proc.returns(StepOutcome)).returns(OperationOutcome) }
    def call(&blk)
      committed = T.let(false, T::Boolean)
      message = T.let(nil, T.nilable(T.any(
        Fulfillment::V1::ReserveStockResponse,
        Fulfillment::V1::ReleaseStockResponse
      )))

      ApplicationRecord.transaction(requires_new: true) do
        self.class.apply_lock_timeout!

        record = claim

        outcome = blk.call
        message = outcome.message
        raise ActiveRecord::Rollback unless outcome.commit

        record.update!(response: outcome.message.to_proto, applied: outcome.applied)
        committed = true
      end

      OperationOutcome.new(
        message: T.must(message),
        status: committed ? OperationOutcome::FRESH : OperationOutcome::REFUSED
      )
    rescue ActiveRecord::RecordNotUnique
      replay
    rescue ClaimTimeout
      retry_later(IN_PROGRESS, "an identical request is still being processed")
    rescue LedgerTimeout
      retry_later(
        LEDGER_BUSY,
        "another call for this order and sku is still in flight; nothing was changed, try again"
      )
    rescue ActiveRecord::LockWaitTimeout
      retry_later(
        LOCK_TIMEOUT,
        "another order is holding this sku's bin rows; nothing was changed, try again"
      )
    end

    private

    sig { returns(StockOperation) }
    def claim
      StockOperation.create!(
        operation: @operation,
        idempotency_key: @key,
        request_digest: @digest,
        merchant: @merchant,
        order_number: @order_number,
        sku: @sku,
        quantity: @quantity,
        response: "",
        first_request_id: request_id
      )
    rescue ActiveRecord::LockWaitTimeout
      raise ClaimTimeout
    end

    sig { returns(OperationOutcome) }
    def replay
      StockOperation.transaction(requires_new: true) do
        record = StockOperation.lock("FOR UPDATE").find_by(
          merchant_id: @merchant.id, operation: @operation, idempotency_key: @key
        )

        next retry_later(IN_PROGRESS, "the original attempt is no longer on record") if record.nil?

        next conflict_outcome(record) if record.request_digest != @digest

        message = decode(record.response.to_s)

        if @operation == StockOperation::RESERVE && message.success && !still_held?(record)
          record.update!(
            replay_refused_count: record.replay_refused_count.to_i + 1,
            last_replay_request_id: request_id
          )

          next OperationOutcome.new(
            message: refusal(
              RESERVATION_RELEASED,
              "the stock this key reserved has since been released"
            ),
            status: OperationOutcome::REPLAY_REFUSED
          )
        end

        record.update!(
          replay_count: record.replay_count.to_i + 1,
          last_replay_request_id: request_id
        )

        OperationOutcome.new(message: message, status: OperationOutcome::REPLAYED)
      end
    rescue LedgerTimeout
      retry_later(
        LEDGER_BUSY,
        "another call for this order and sku is still in flight; nothing was changed, try again"
      )
    rescue ActiveRecord::LockWaitTimeout
      retry_later(IN_PROGRESS, "an identical request is still being processed")
    end

    sig { params(record: StockOperation).returns(T::Boolean) }
    def still_held?(record)
      reservation = StockReservation.lock("FOR UPDATE").find_by(
        merchant_id: record.merchant_id,
        order_number: record.order_number,
        sku: record.sku
      )

      !reservation.nil? && reservation.held?
    rescue ActiveRecord::LockWaitTimeout
      raise LedgerTimeout
    end

    sig { params(record: StockOperation).returns(OperationOutcome) }
    def conflict_outcome(record)
      record.update!(conflict_count: record.conflict_count.to_i + 1)

      OperationOutcome.new(
        message: refusal(
          KEY_CONFLICT,
          "that idempotency key was already used for a different request"
        ),
        status: OperationOutcome::CONFLICT
      )
    end

    sig { params(code: String, text: String).returns(OperationOutcome) }
    def retry_later(code, text)
      OperationOutcome.new(
        message: refusal(code, text),
        status: OperationOutcome::RETRY_LATER
      )
    end

    sig do
      params(bytes: String).returns(T.any(
        Fulfillment::V1::ReserveStockResponse,
        Fulfillment::V1::ReleaseStockResponse
      ))
    end
    def decode(bytes)
      if @operation == StockOperation::RESERVE
        Fulfillment::V1::ReserveStockResponse.decode(bytes)
      else
        Fulfillment::V1::ReleaseStockResponse.decode(bytes)
      end
    end

    sig do
      params(code: String, text: String).returns(T.any(
        Fulfillment::V1::ReserveStockResponse,
        Fulfillment::V1::ReleaseStockResponse
      ))
    end
    def refusal(code, text)
      detail = Common::V1::ErrorDetail.new(error_code: code, message: text)

      if @operation == StockOperation::RESERVE
        Fulfillment::V1::ReserveStockResponse.new(
          success: false, bin_location: "N/A", remaining_available: 0, error: detail
        )
      else
        Fulfillment::V1::ReleaseStockResponse.new(
          success: false, already_released: false, remaining_available: 0, error: detail
        )
      end
    end

    sig { returns(String) }
    def request_id
      Kinetix::RequestId.current.to_s
    end
  end
end
