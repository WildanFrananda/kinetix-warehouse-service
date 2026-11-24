# 📦 Kinetix Warehouse OMS (`kinetix-warehouse-service`)

Enterprise Warehouse Order Management, Physical Bin Inventory Tracking, Packing, Shipping Label AWB Generation, and Courier Dispatch microservice built with **Ruby 3.3+**, **Rails 8.0+**, **Sorbet Static Type System (`# typed: strict`)**, **Phlex UI Components**, **Hotwire Live Dashboard**, **gRPC Server (`:50051`)**, and **PostgreSQL 16**.

---

## 🏛️ Resolved Audit Upgrades & Production Hardening

1. **Single Source of Truth Identity Integration**:
   - `SessionsController` integrates with `Identity::GrpcClient` to authenticate warehouse staff via gRPC `IdentityService` (`:50052`), resolving identity sovereignty violations.
2. **0 Sorbet Typecheck Errors**:
   - Resolved all 17 Sorbet typecheck errors (`bundle exec srb tc` ➔ **`No errors! Great job.`**). Aligned Protobuf class names (`CheckBinStockResponse`), fields (`req.quantity`), and keyword arguments (`success:`, `bin_location:`, `remaining_available:`).
3. **gRPC Order & Identity Integration**:
   - `Identity::GrpcClient` (`:50052`) and `Order::GrpcClient` (`:50055`) communicate over mutual TLS gRPC with fail-fast environment configuration.
4. **Real Physical Inventory Stock Queries**:
   - Eliminated `available_stock + 5` and fake 25 items fallback in `BinStockServiceHandler`. Returns exact physical inventory counts from `BinInventory` and `WarehouseBin` tables.
5. **RSpec Test Suite Verification**:
   - Executed `bundle exec rspec` ➔ **`36 examples, 0 failures (100% Passed)`**.

---

## 📂 Complete Repository Directory Structure

```
kinetix-warehouse-service/
├── app/
│   ├── clients/                        # External gRPC Clients
│   │   ├── identity/                   # gRPC Identity Client (:50052)
│   │   └── order/                      # gRPC Order Client (:50055)
│   ├── controllers/                    # Rails Controllers
│   ├── models/                         # Sorbet ActiveRecord Models
│   │   ├── warehouse_bin.rb
│   │   ├── bin_inventory.rb
│   │   ├── order.rb
│   │   ├── order_item.rb
│   │   ├── shipping_label.rb
│   │   └── return.rb
│   ├── rpc/                            # Inbound gRPC Handlers (:50051)
│   │   ├── bin_stock_service_handler.rb
│   │   └── fulfillment_service_handler.rb
│   └── views/                          # Phlex UI Components & Hotwire Dashboard
├── config/
├── db/                                 # PostgreSQL 16 Schema & Migrations
├── lib/
│   └── generated/                      # Protobuf Stubs
└── spec/                               # RSpec Test Suite (36 examples, 0 failures)
```

---

## ⚡ Local Execution & Verification Commands

```bash
# 1. Run Sorbet Typecheck
bundle exec srb tc

# 2. Run Complete RSpec Test Suite
bundle exec rspec

# 3. Start Rails OMS Server
bundle exec rails server -p 3000
```
