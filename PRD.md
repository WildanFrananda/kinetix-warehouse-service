# PRD: Same-Day Delivery Fulfillment Platform for Local Muslim Fashion E-Commerce

**Status:** Active Enterprise Architecture
**Owner:** Wildan
**Last updated:** 14 August 2026

---

## 1. Background & Problem Statement

Local Muslim-fashion boutiques and e-commerce platforms (hijab, gamis, koko, mukena, etc.) frequently receive orders from buyers who need the item **on the same day** — for a *kondangan*, *pengajian*, or last-minute event. Today this is handled manually: WhatsApp order confirmations, Excel/Google Sheets for tracking, and phone calls to couriers. This causes:

- No single source of truth for order status between the merchant's warehouse staff, courier, and buyer.
- No guarantee mechanism for same-day SLA — orders silently slip to next-day delivery.
- Returns/exchanges (common in fashion — size, color mismatch) are tracked manually, causing inventory discrepancies.
- Multiple boutiques/brands share the same operator team (common in Indonesian fashion aggregator/reseller networks), risking **data leakage** between competing brands (order volume, buyer data, courier routes).

---

## 2. Goal

Build a Rails-based **Order Management System (OMS)** that gives boutique warehouse staff and merchant brand owners a real-time operational screen to:
1. See incoming orders that require same-day fulfillment, prioritized by cutoff time.
2. Print shipping labels/AWB per order with Code128 vector barcodes.
3. Track courier pickup → delivery status in real time via Kinetix Matching Elixir Radar.
4. Manage returns without leaking data across tenants (brands).
5. Configure merchant API credentials, SLA cutoff hours, and warehouse staff access.

---

## 3. Comprehensive User Role Matrix & Requirements

The platform serves **4 distinct operational user roles**, each requiring tailored capabilities:

| User Role | Persona & Access Scope | Dedicated Screen / Route | Specialized Features & Missing Scope Roadmap |
|---|---|---|---|
| **1. Warehouse Manager** | Executive Operations Lead (`Budi Hendra`, `Siti Nurhaliza`) | `/analytics`, `/settings`, `/orders`, `/support` | - **RBAC & Authentication**: User login (`/login`) with role permissions.<br>- **Emergency Halt**: Warehouse emergency override button.<br>- **Audit Log**: Digital trail of staff actions.<br>- **Cutoff Triage**: Override same-day SLA cutoff for VIP orders.<br>- **Staff Leaderboard**: Packing productivity per shift. |
| **2. Picker & Packer Staff** | Warehouse Physical Operations Staff | `/orders`, `/inventory`, `/manifests`, `/scan` | - **Bin Location Finder**: Physical bin mapping (`Rak A-01, Bin 12`).<br>- **JsBarcode Engine**: 100mm x 150mm thermal AWB sticker.<br>- **Handover PDF**: Printable Surat Jalan PDF.<br>- **PDA Barcode Mode (`/scan`)**: Camera/laser barcode scanning for hands-free pick/pack validation.<br>- **Wave Picking**: Batch route picking for 50 orders simultaneously.<br>- **Scale Check**: Digital weight scale validation. |
| **3. Brand Merchant** | E-Commerce Store Owner (`Boutique Hijab Premium`, `Gamis Elegant Style`) | `/settings`, `/inventory`, `/api/v1/orders` | - **Isolated Portal View**: Strict tenant isolation for merchant owners.<br>- **API Key Management**: Production API keys & Webhook URL configuration.<br>- **Marketplace Sync**: Real-time stock sync with Shopify/TikTok/Tokopedia.<br>- **Inbound PO (`/inbound`)**: Booking schedule for new stock arrival from factory. |
| **4. Courier** | Instant Delivery Driver (Kinetix Matching Elixir Cluster) | `/fleet_radar`, `/driver_app` | - **Driver Radar (`/fleet_radar`)**: Live GPS telemetry stream (speed, ETA, coordinates).<br>- **Pickup Request**: Real-time dispatch trigger.<br>- **Driver Mobile PWA (`/driver_app`)**: Driver app to accept tasks & update status.<br>- **Proof of Delivery (POD)**: Photo attachment & digital signature on delivery. |

---

## 4. Core User Stories

1. As a **warehouse staff**, I want to see all orders due for same-day delivery sorted by cutoff time, so I can prioritize picking and packing.
2. As a **warehouse staff**, I want to print a shipping label directly from the order detail, so I don't need a separate system.
3. As a **merchant owner**, I want order and courier status to update live on the operational screen without refreshing, so my staff always has current information.
4. As an **operator managing multiple brands**, I want to be certain that switching to Brand A's dashboard never shows Brand B's orders, couriers, or buyer data.
5. As a **warehouse staff**, I want to register a return/exchange against an order, so inventory and refund status stay accurate.
6. As a **merchant owner**, I want to see how many orders missed the same-day SLA this week, so I can identify bottlenecks.
7. As a **warehouse manager**, I want an Emergency Halt button to pause automated courier dispatches during warehouse hardware or logistics outages.

---

## 5. Functional Requirements & Completed Modules

### 5.1 Module 1: Order Queue Pipeline (`/orders`)
- Connected pipeline stepper bar: `All Orders` → `1. Received` → `2. Packing` → `3. Packed` → `4. Dispatched`.
- 3-Column Glassmorphic Cards Grid matching **Obsidian Control** design system (`#0b1326`, `Outfit`, `Plus Jakarta Sans`, `JetBrains Mono`).
- **`+ New Manual Order`**: Glassmorphic modal form creating real DB records via `Orders::CreateOrderService` & `Orders::CreateOrderForm`.
- **`⚡ Filter Order Queue`**: Smooth slide-over drawer (`cubic-bezier` transition) with Date Range, SLA Urgency Multi-select, Status Grid, and Merchant filter.
- **`🚨 Emergency Halt`**: Instant warehouse override dispatch pause.

### 5.2 Module 2: Kinetix Matching Driver Radar (`/fleet_radar`)

- Live GPS telemetry stream (latitude, longitude, speed in km/h, ETA countdown, call driver action).
- Real-time driver status tracking for `dispatched`, `in_transit`, and `delivered` orders.

### 5.3 Module 3: Returns & Exchange Processing Hub (`/returns`)
- Customer return claims processing hub with interactive QA state machine buttons (`Mark Picked Up`, `Receive at Warehouse`, `Pass QA & Inspect`, `Resolve & Issue Exchange`).

### 5.4 Module 4: Inventory & Bin Location Finder (`/inventory`)
- Warehouse rack bin mapping (`Rak A-01, Bin 12`), 3-tier stock levels (Physical, Allocated, Available) derived dynamically from PostgreSQL `order_items.bin_location` records.

### 5.5 Module 5: SLA Compliance & Analytics Dashboard (`/analytics`)
- SLA On-time compliance rate (%), total active orders, overdue SLA violations, total GMV revenue, top selling fashion products ranking table.

### 5.6 Module 6: Batch Label Print & Driver Handover Manifest (`/manifests`)
- Printable A4 Surat Jalan Serah Terima Driver PDF (`/manifests/handover_pdf`) with dynamic manifest reference, package list, dual signature boxes, and vector Code128 barcode engine.

### 5.7 Module 7: Merchant & Warehouse Settings (`/settings`)
- Production API Key management (`luxe_prod_sec_...`) with JS Clipboard copy button & POST regeneration action.
- Same-Day SLA Cutoff hour selector (e.g. `14:00 WIB`) updating `merchants.cutoff_hour` in PostgreSQL.
- Integration Endpoints card (`REST API v1` & `Action Cable WebSocket`) with live ping diagnostic.

### 5.8 Module 8: Support & Help Center (`/support`)
- Real-time System Health diagnostics:
  - `PostgreSQL DB`: Real ActiveRecord connection check (`ActiveRecord::Base.connection.active?`).
  - `Action Cable`: Real HTTP WebSocket Upgrade handshake check (`Net::HTTP` GET to `/cable`).
  - `Phoenix WebSocket`: Real TCP socket ping (`TCPSocket.new('localhost', 4000)`).
- Interactive Glassmorphic Modals for Warehouse SLA SOP, Elixir API Docs, Emergency Protocol, and Support Ticket Escalation.

---

## 6. System Architecture & Strict Rules

### 6.1 Strict Engineering Directives (`AGENTS.md`)
- **No Direct Code Editing Rule**: AI agent outputs code in chat; user reviews and executes.
- **Strict Sorbet Typing (`# typed: strict`)**: All files under `app/` MUST start with `# typed: strict` and include complete `sig` annotations.
- **Strict Prohibition of Hardcoded Values**: No hardcoded dummy strings, IDs, or fallback URLs. All data is dynamically derived from PostgreSQL database records or environment parameters.
- **Demo Data Via Seeder Only**: All test/demo data populated strictly through `db/seeds.rb` using dynamic catalog matrices and calculation logic.
- **Strict Prohibition of Pseudo-Random & Dummy Math Fallbacks**: Generating fake metrics or latencies using `rand()` or modulo offsets is strictly prohibited. All metrics derived from real database records or MONOTONIC clock socket benchmarks (`Process.clock_gettime(Process::CLOCK_MONOTONIC)`).

---

## 7. Phased Expansion Roadmap

### Phase 1 — Core OMS & Design System (COMPLETED ✅)
- Multi-tenant architecture, 8 enterprise modules, vector Code128 barcode engine, Obsidian Control design system, logic-driven seeder, and Sorbet strict type-safety.

### Phase 2 — Role Access Control & Mobile PDA Scan (UPCOMING 🚀)
- **Role-Based Authentication (`/login`)**: Devise / Session RBAC for Manager vs Staff vs Merchant.
- **PDA Mobile Barcode Scanner Mode (`/scan`)**: Camera/laser barcode scanning interface for hands-free pick/pack validation.
- **Driver Mobile Web App (`/driver_app`)**: Driver task acceptance & Proof of Delivery (POD photo) attachment.

### Phase 3 — Advanced Warehouse Logistics & Pure Microservices Strategy (IN PROGRESS 🚀)
- **Pure Warehouse Scope**: Keep `fashion_fulfillment_oms` 100% focused on warehouse operations, bin locations, packing scanner verification, shipping labels, and driver dispatch without monolithic bloat (no storefront cart or payment gateway logic in OMS).
- **Storefront Microservice Ingress**: External storefront microservices (E-Commerce A, E-Commerce B, etc.) connect via gRPC for order creation & status inquiries.
- **Wave Picking Engine**: Batch route optimization for 50+ orders.
- **Inbound Stock Booking (`/inbound`)**: Advanced Shipping Notice (ASN) for factory shipments.
- **Marketplace Auto-Sync**: Webhook engine for TikTok Shop, Shopify, and Tokopedia.

---

## 8. Success Metrics

- **Same-day fulfillment rate** ≥ 95% of eligible orders shipped within cutoff window.
- **Time from order-received to packed** median < 20 minutes during business hours.
- **Zero cross-tenant data incidents** (Strict database `merchant_id` constraint).
- **100% Sorbet Strict Type Compliance (`bundle exec srb tc`)**.

---

## 9. Approved Enterprise Microservices & gRPC Architecture Blueprint

> **Status:** Officially Approved Architectural Blueprint  
> **Master Reference Artifact:** `microservices_grpc_migration_plan.md`

### 9.1 Multi-Tenant Microservices Domain Separation
To prevent monolithic bloat, the ecosystem is strictly decoupled into single-responsibility microservices:

1. **Storefront Microservice (External / Future Projects)**:
   - Responsible for Product Catalog, Storefront Display, Cart, Customer Auth, and Payment Gateways (Midtrans, Xendit, QRIS).
   - Operates independently for E-Commerce A, E-Commerce B, etc.
   - Communicates with OMS via **gRPC Protobuf** on Port `50051` as soon as payment is confirmed (`status: paid`).

2. **Warehouse Fulfillment OMS Engine (`fashion_fulfillment_oms` — Rails 8)**:
   - Dedicated warehouse fulfillment engine (`# typed: strict`).
   - Responsible for Order Queue Triage, Warehouse Bin Picking (`bin_location`), Barcode Scanner Packing Verification (`/scan`), Thermal Shipping Label PDF Generation, and Fleet Dispatch Triggers.

3. **Fleet & Telemetry Microservice (`kinetix-matching-service` — Elixir / Phoenix)**:
   - Dedicated real-time courier telemetry cluster (`ws://localhost:4000/socket/websocket`).
   - Responsible for Live GPS Telemetry, Driver Duty Status, and Push Notifications to Driver App (`kinetix-courier-mobile`).

### 9.2 Inter-Service Protocol & Contract Specifications (`fulfillment_service.proto`)
- **Inter-Service Communication**: gRPC (Google Remote Procedure Call) over HTTP/2 using binary Protocol Buffers (`.proto`).
- **Target Response Time**: < 5ms for synchronous RPC calls (`CreateOrder`, `GetOrderStatus`, `CancelOrder`, `CheckBinStock`).
- **Multi-Tenant Security**: gRPC Metadata Header `x-merchant-api-key` verified against PostgreSQL `merchants.api_key`.

### 9.3 Real-Time Streaming Matrix
- **Driver App ↔ Elixir Telemetry**: Bi-directional **WebSockets (WS)** for instant GPS pings and task assignment.
- **OMS Supervisor Fleet Radar (`/fleet_radar`)**: **Action Cable WebSockets** streaming dynamic courier position markers (`latitude`, `longitude`, `speed_kmh`, `eta_minutes`).
- **Customer Order Tracking Screen**: **Server-Sent Events (SSE)** (`text/event-stream`) 1-way stream for battery-efficient mobile live tracking.

### 9.4 Database Migration & Hardcoding Prohibition Rule
- **No Hardcoded Fallbacks Rule**: Hardcoding fallback values (coordinates, status codes, dummy arrays) inside controllers or models is strictly prohibited. If a database table lacks required fields (such as `latitude` & `longitude` on `merchants`), proper ActiveRecord migrations, model attributes, and Sorbet `# typed: strict` signatures MUST be created instead.