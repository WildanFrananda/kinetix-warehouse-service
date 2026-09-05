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
      reserved = inventory.reserved_quantity || 0

      Fulfillment::V1::CheckBinStockResponse.new(
        found: true,
        sku: sku,
        product_name: "Physical Inventory SKU #{sku}",
        physical_stock: inventory.quantity || (available + reserved),
        allocated_stock: reserved,
        available_stock: available,
        bin_location: inventory.warehouse_bin.bin_code,
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
        return Fulfillment::V1::ReserveStockResponse.new(
          success: false,
          bin_location: "",
          remaining_available: 0,
          error: Common::V1::ErrorDetail.new(
            error_code: "UNKNOWN_MERCHANT",
            message: "no merchant in this warehouse is linked to that principal"
          )
        )
      end

      sku = req.sku
      req_qty = req.quantity

      lock_key = "lock:inventory:#{sku}"
      lock_acquired = false

      begin
        lock_acquired = REDIS.set(lock_key, "locked", nx: true, px: 3000) == "OK"
      rescue StandardError => e
        Rails.logger.warn("Redis Tier-1 Lock unavailable: #{e.message}")
        lock_acquired = true
      end

      unless lock_acquired
        return Fulfillment::V1::ReserveStockResponse.new(
          success: false,
          bin_location: "N/A",
          remaining_available: 0
        )
      end

      success = T.let(false, T::Boolean)
      bin_code = T.let("N/A", String)
      remaining = T.let(0, Integer)

      begin
        BinInventory.transaction do
          inventory = BinInventory.lock("FOR UPDATE").joins(:warehouse_bin).find_by(sku: sku)

          if inventory.nil?
            success = false
            bin_code = "N/A"
            remaining = 0
          elsif inventory.available_quantity >= req_qty
            new_reserved = (inventory.reserved_quantity || 0) + req_qty
            inventory.update!(reserved_quantity: new_reserved)
            success = true
            bin_code = inventory.warehouse_bin.bin_code
            remaining = inventory.available_quantity

            begin
              REDIS.set("inventory:available:#{sku}", remaining.to_s)
            rescue StandardError => e
              Rails.logger.warn("Failed to update Redis inventory cache: #{e.message}")
            end
          else
            success = false
            bin_code = inventory.warehouse_bin.bin_code
            remaining = inventory.available_quantity
          end
        end
      ensure
        begin
          REDIS.del(lock_key)
        rescue StandardError => e
          Rails.logger.warn("Failed to release Redis lock: #{e.message}")
        end
      end

      Fulfillment::V1::ReserveStockResponse.new(
        success: success,
        bin_location: bin_code,
        remaining_available: remaining
      )
    end

    sig do
      params(
        _req: Fulfillment::V1::ReleaseStockRequest,
        _call: T.nilable(GRPC::ActiveCall::SingleReqView)
      ).returns(Fulfillment::V1::ReleaseStockResponse)
    end
    def release_stock(_req, _call)
      raise GRPC::Unimplemented, "ReleaseStock lands with the idempotency ledger in S10"
    end

    private

    sig { params(principal_id: String).returns(T.nilable(Merchant)) }
    def merchant_for(principal_id)
      return nil if principal_id.empty?

      Merchant.find_by(principal_id: principal_id)
    end
  end
end
