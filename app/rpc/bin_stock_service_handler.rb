# typed: strict
# frozen_string_literal: true

require "fulfillment/v1/fulfillment_services_pb"

module Rpc
  class BinStockServiceHandler < Fulfillment::V1::BinStockService::Service
    extend T::Sig

    NOT_FOUND_STOCK = T.let(
      Fulfillment::V1::CheckBinStockResponse.new(found: false),
      Fulfillment::V1::CheckBinStockResponse
    )

    UNKNOWN_MERCHANT = "UNKNOWN_MERCHANT"
    INVALID_ARGUMENT = "INVALID_ARGUMENT"

    sig { void }
    def initialize
      super
    end

    sig do
      params(
        req: Fulfillment::V1::CheckBinStockRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::CheckBinStockResponse)
    end
    def check_bin_stock(req, _call)
      merchant = merchant_for(req.merchant_principal_id)
      return NOT_FOUND_STOCK if merchant.nil?

      sku = req.sku
      inventory = BinInventory.joins(:warehouse_bin).find_by(sku: sku)

      return NOT_FOUND_STOCK if inventory.nil?

      available = inventory.available_quantity
      reserved = inventory.reserved_quantity

      Fulfillment::V1::CheckBinStockResponse.new(
        found: true,
        sku: sku,
        product_name: "Physical Inventory SKU #{sku}",
        physical_stock: inventory.quantity,
        allocated_stock: reserved,
        available_stock: available,
        bin_location: inventory.warehouse_bin&.bin_code.to_s,
        low_stock_warning: available < 5
      )
    end

    sig do
      params(
        req: Fulfillment::V1::CheckBinStockRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::CheckBinStockResponse)
    end
    def get_bin_stock_info(req, _call)
      check_bin_stock(req, _call)
    end

    sig do
      params(
        req: Fulfillment::V1::ReserveStockRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::ReserveStockResponse)
    end
    def reserve_stock(req, _call)
      merchant = merchant_for(req.merchant_principal_id)
      if merchant.nil?
        return reserve_refusal(
          UNKNOWN_MERCHANT, "no merchant in this warehouse is linked to that principal"
        )
      end

      if req.quantity < 1
        return reserve_refusal(INVALID_ARGUMENT, "quantity must be at least 1")
      end

      key = idempotency_key(StockOperation::RESERVE, req)
      if key.nil?
        return reserve_refusal(INVALID_ARGUMENT, invalid_argument_reason(req))
      end

      outcome = Inventory::IdempotentOperation.new(
        operation: StockOperation::RESERVE,
        key: key,
        digest: StockOperation.digest_of(
          [
            StockOperation::RESERVE, merchant.principal_id.to_s,
            req.order_number, req.sku, req.quantity.to_s
          ]
        ),
        merchant: merchant,
        order_number: req.order_number,
        sku: req.sku,
        quantity: req.quantity
      ).call do
        Inventory::ReserveStockService.new(
          merchant: merchant, order_number: req.order_number,
          sku: req.sku, quantity: req.quantity
        ).call
      end

      log_outcome(StockOperation::RESERVE, key, req.order_number, req.sku, outcome)
      T.cast(outcome.message, Fulfillment::V1::ReserveStockResponse)
    end

    sig do
      params(
        req: Fulfillment::V1::ReleaseStockRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::ReleaseStockResponse)
    end
    def release_stock(req, _call)
      merchant = merchant_for(req.merchant_principal_id)
      if merchant.nil?
        return release_refusal(
          UNKNOWN_MERCHANT, "no merchant in this warehouse is linked to that principal"
        )
      end

      key = idempotency_key(StockOperation::RELEASE, req)
      if key.nil?
        return release_refusal(INVALID_ARGUMENT, invalid_argument_reason(req))
      end

      outcome = Inventory::IdempotentOperation.new(
        operation: StockOperation::RELEASE,
        key: key,
        digest: StockOperation.digest_of(
          [ StockOperation::RELEASE, merchant.principal_id.to_s, req.order_number, req.sku ]
        ),
        merchant: merchant,
        order_number: req.order_number,
        sku: req.sku,
        quantity: req.quantity
      ).call do
        Inventory::ReleaseStockService.new(
          merchant: merchant, order_number: req.order_number, sku: req.sku
        ).call
      end

      log_outcome(StockOperation::RELEASE, key, req.order_number, req.sku, outcome)
      T.cast(outcome.message, Fulfillment::V1::ReleaseStockResponse)
    end

    private

    sig do
      params(
        operation: String,
        req: T.any(Fulfillment::V1::ReserveStockRequest, Fulfillment::V1::ReleaseStockRequest)
      ).returns(T.nilable(String))
    end
    def idempotency_key(operation, req)
      return nil if req.order_number.blank? || req.sku.blank?
      return nil if req.order_number.length > StockOperation::MAX_ORDER_NUMBER_LENGTH
      return nil if req.sku.length > StockOperation::MAX_SKU_LENGTH

      key = req.idempotency_key&.key.presence || "#{operation}:#{req.order_number}:#{req.sku}"
      return nil if key.length > StockOperation::MAX_KEY_LENGTH

      key
    end

    sig do
      params(
        req: T.any(Fulfillment::V1::ReserveStockRequest, Fulfillment::V1::ReleaseStockRequest)
      ).returns(String)
    end
    def invalid_argument_reason(req)
      return "order_number is required" if req.order_number.blank?
      return "sku is required" if req.sku.blank?

      if req.order_number.length > StockOperation::MAX_ORDER_NUMBER_LENGTH
        return "order_number must be at most #{StockOperation::MAX_ORDER_NUMBER_LENGTH} characters"
      end

      if req.sku.length > StockOperation::MAX_SKU_LENGTH
        return "sku must be at most #{StockOperation::MAX_SKU_LENGTH} characters"
      end

      "idempotency_key must be at most #{StockOperation::MAX_KEY_LENGTH} characters"
    end

    sig do
      params(
        operation: String, key: String, order_number: String, sku: String,
        outcome: Inventory::OperationOutcome
      ).void
    end
    def log_outcome(operation, key, order_number, sku, outcome)
      context = "operation=#{operation} key=#{key} order_number=#{order_number} sku=#{sku} " \
                "(request_id=#{Kinetix::RequestId.current || '-'})"

      case outcome.status
      when Inventory::OperationOutcome::REPLAYED
        Rails.logger.warn("stock.idem replay #{context}")
      when Inventory::OperationOutcome::REPLAY_REFUSED
        Rails.logger.error(
          "stock.idem replay_refused error_code=#{outcome.message.error&.error_code} #{context}"
        )
      when Inventory::OperationOutcome::CONFLICT
        Rails.logger.error("stock.idem conflict #{context}")
      when Inventory::OperationOutcome::RETRY_LATER
        Rails.logger.error("stock.idem retry_later #{context}")
      when Inventory::OperationOutcome::REFUSED
        Rails.logger.warn(
          "stock.idem refused error_code=#{outcome.message.error&.error_code} #{context}"
        )
      end
    end

    sig { params(code: String, text: String).returns(Fulfillment::V1::ReserveStockResponse) }
    def reserve_refusal(code, text)
      Fulfillment::V1::ReserveStockResponse.new(
        success: false,
        bin_location: "N/A",
        remaining_available: 0,
        error: Common::V1::ErrorDetail.new(error_code: code, message: text)
      )
    end

    sig { params(code: String, text: String).returns(Fulfillment::V1::ReleaseStockResponse) }
    def release_refusal(code, text)
      Fulfillment::V1::ReleaseStockResponse.new(
        success: false,
        already_released: false,
        remaining_available: 0,
        error: Common::V1::ErrorDetail.new(error_code: code, message: text)
      )
    end

    sig { params(principal_id: String).returns(T.nilable(Merchant)) }
    def merchant_for(principal_id)
      return nil if principal_id.empty?

      Merchant.find_by(principal_id: principal_id)
    end
  end
end
