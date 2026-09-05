# typed: strict
# frozen_string_literal: true

require_relative "../../lib/generated/fulfillment/v1/bin_stock_service_services_pb"

module Rpc
  class BinStockServiceHandler < Fulfillment::V1::BinStockService::Service
    extend T::Sig

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
      sku = req.sku
      inventory = BinInventory.joins(:warehouse_bin).find_by(sku: sku)

      if inventory
        available = inventory.available_quantity
        reserved = inventory.reserved_quantity || 0
        physical = inventory.quantity || (available + reserved)
        bin_code = inventory.warehouse_bin.bin_code
      else
        available = 0
        reserved = 0
        physical = 0
        bin_code = "Unavailable"
      end

      Fulfillment::V1::CheckBinStockResponse.new(
        sku: sku,
        product_name: "Physical Inventory SKU #{sku}",
        physical_stock: physical,
        allocated_stock: reserved,
        available_stock: available,
        bin_location: bin_code,
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
  end
end
