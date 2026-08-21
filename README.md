# 📦 Kinetix Warehouse OMS (`kinetix-warehouse-service`)

Enterprise Warehouse Order Management, Physical Bin Inventory Tracking, Packing, Shipping Label AWB Generation, and Courier Dispatch microservice built with **Ruby 3.3+**, **Rails 8.0+**, **Sorbet Static Type System (`# typed: strict`)**, **Phlex UI Components**, **Hotwire Live Dashboard**, **gRPC Server (`:50051`)**, and **PostgreSQL 16**.

---

## 🏛️ Resolved Audit Items & Architectural Upgrades

1. **Physical Warehouse Bin & Inventory Tables**:
   - Implemented `WarehouseBin` (`bin_code`, `zone`, `shelf_level`) and `BinInventory` (`sku`, `quantity`, `reserved_quantity`, `available_quantity`) models and PostgreSQL 16 migrations.
2. **Real Physical Inventory Stock Queries**:
   - `BinStockServiceHandler` and `InventoryController` query real physical `BinInventory` database records instead of hardcoded numbers.
3. **Fixed gRPC Target Port (`FleetPulseClient`)**:
   - Updated `FleetPulseClient` default host configuration to `ENV.fetch("MATCHING_GRPC_HOST", "localhost:4000")`.
4. **Dynamic Merchant Key Parameter Handling (`Identity::GrpcClient`)**:
   - Updated `Identity::GrpcClient#get_merchant_by_api_key` to dynamically extract merchant parameters instead of using static values.
5. **Strict Sorbet Static Typing & RSpec Suite**:
   - `# typed: strict` enforced across models, handlers, and clients (`bundle exec rspec` ➔ **`36 examples, 0 failures`**).

---

## 📂 Complete File Directory Structure (Rails 8 OMS)

```
kinetix-warehouse-service/
├── app/
│   ├── clients/                        # External gRPC Clients (Identity & Matching)
│   │   ├── identity_client.rb          # Identity gRPC Client (:50052)
│   │   └── fleet_pulse_client.rb       # Matching gRPC Client (:4000)
│   ├── models/                         # Sorbet Active Record Models
│   │   ├── warehouse_bin.rb
│   │   ├── bin_inventory.rb
│   │   ├── order.rb
│   │   ├── order_item.rb
│   │   ├── shipping_label.rb
│   │   └── return.rb
│   ├── rpc/                            # Inbound gRPC Handlers (:50051)
│   │   ├── bin_stock_service_handler.rb
│   │   └── fulfillment_service_handler.rb
│   └── views/                          # Phlex Components & Hotwire Dashboard
├── config/
├── db/
│   ├── migrate/                        # PostgreSQL 16 Migrations
│   └── schema.rb
├── lib/
│   └── generated/                      # Generated Protobuf Stubs
└── spec/                               # Complete RSpec Test Suite (36 examples, 0 failures)
```

---

## ⚡ Local Setup & Test Execution Guide

```bash
# 1. Prepare PostgreSQL 16 Database
bundle exec rails db:prepare

# 2. Run Complete RSpec Test Suite
bundle exec rspec

# 3. Start Rails OMS & Inbound gRPC Server (:50051)
bundle exec rails server -p 3000
```
