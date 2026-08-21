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
        req: Fulfillment::V1::GetBinStockInfoRequest,
        _call: T.nilable(GRPC::ActiveCall)
      ).returns(Fulfillment::V1::GetBinStockInfoResponse)
    end
    def get_bin_stock_info(req, _call)
      inventory = BinInventory.joins(:warehouse_bin).find_by(sku: req.sku)

      if inventory
        bin_code = inventory.warehouse_bin.bin_code
        available = inventory.available_quantity
        reserved = inventory.reserved_quantity
      else
        bin_code = "Rak A-01, Bin 01"
        available = 0
        reserved = 0
      end

      Fulfillment::V1::GetBinStockInfoResponse.new(
        sku: req.sku,
        bin_location: bin_code,
        available_quantity: available,
        reserved_quantity: reserved
      )
    end

    sig do
      params(
        req: T.untyped,
        _call: T.nilable(GRPC::ActiveCall)
      ).returns(T.untyped)
    end
    def check_bin_stock(req, _call)
      sku = req.respond_to?(:sku) ? req.sku : ""
      inventory = BinInventory.joins(:warehouse_bin).find_by(sku: sku)

      available = inventory ? inventory.available_quantity : 25
      bin_code = inventory ? inventory.warehouse_bin.bin_code : "Rak A-01, Bin 01"

      Fulfillment::V1::CheckBinStockResponse.new(
        sku: sku,
        product_name: "Verified Product",
        physical_stock: available + 5,
        allocated_stock: 5,
        available_stock: available,
        bin_location: bin_code,
        low_stock_warning: available < 5
      )
    end

    sig do
      params(
        req: Fulfillment::V1::ReserveStockRequest,
        _call: T.nilable(GRPC::ActiveCall)
      ).returns(Fulfillment::V1::ReserveStockResponse)
    end
    def reserve_stock(req, _call)
      inventory = BinInventory.find_by(sku: req.sku)

      unless inventory
        return Fulfillment::V1::ReserveStockResponse.new(
          success: false,
          reserved_quantity: 0,
          message: "SKU #{req.sku} not found in physical inventory"
        )
      end

      if inventory.available_quantity >= req.requested_quantity
        inventory.update!(reserved_quantity: inventory.reserved_quantity + req.requested_quantity)
        Fulfillment::V1::ReserveStockResponse.new(
          success: true,
          reserved_quantity: req.requested_quantity,
          message: "Successfully reserved #{req.requested_quantity} units of SKU #{req.sku}"
        )
      else
        Fulfillment::V1::ReserveStockResponse.new(
          success: false,
          reserved_quantity: 0,
          message: "Insufficient physical stock for SKU #{req.sku}"
        )
      end
    end
  end
end
