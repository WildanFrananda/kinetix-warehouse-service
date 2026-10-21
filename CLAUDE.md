# CLAUDE.md — kinetix-warehouse-service

`AGENTS.md` holds the stack and the verification commands. This file holds decisions that the code
states but cannot explain.

## Fulfillment task status

`Fulfillment::TaskTransitions` is the whole rule. A merchant moves a task forward only —
`received → packing → packed` — and may set `packed` again, which re-sends the report to order when
the first one did not get through. Scanning takes the same steps through `AdvanceTaskService`, the one
path to `packed`, so a scan that packs a parcel tells order (`FulfillmentPacked`) as setting the status
does. When order cannot be reached the task stays packed and `notify_error` says so in fixed words; the
transport's own text goes to the log only. On the returns routes an unreachable order is `503
ORDER_UNAVAILABLE`, and a refusal order gave stays `502 RETURN_NOT_RECORDED` with order's reason.

`cancelled` is not a merchant's to set or to leave. Order cancels a task after it has released the
stock and refunded the buyer; a merchant reaching `cancelled` would leave order waiting on a parcel,
and a merchant leaving it would send order a "packed" report for an order the buyer has been
refunded for. Order refuses such a report too (it accepts "packed" only for a paid order of the same
merchant), but the warehouse does not send it in the first place.

`FulfillmentTaskRepository#update_status` takes `from:` so a move happens only if the task is still
where the caller read it; two requests racing on one task cannot both move it.

## Merchant standing

Identity is asked on every seller request; the local `merchants` row is a key that tasks and stock hang
on, never the answer (the user's ruling of 2026-10-18, `kinetix-infrastructure/docs/MERCHANT-SUSPENSION.md`
§2: no cache, no first-sight row). `ApiAuthentication#require_api_standing!` refuses a token whose role is
not `seller` with `403 NOT_A_SELLER` without asking identity (pricing does the same); a freshly approved
seller gets the role on its next refresh. Then `Merchants::ResolveService` calls `GetMerchantInfo`:
not found is `403 NOT_A_MERCHANT`, an outage is `503 IDENTITY_UNAVAILABLE`, never a refusal.

Per action (same ruling): finishing a paid order (queue, status, scan, label, returns, `GET
/merchants/me`) needs only that identity knows the merchant, so a suspended merchant still ships what
buyers paid for; changing how the store runs (the cutoff hour) needs `may_sell`, else `403
MERCHANT_NOT_TRADING`. "Identity knows it" stands in for `may_fulfil` until that field exists (suspension
plan D1); swap it in `require_api_merchant!` then.

A row is created in one place, `MerchantRepository#project`, after identity vouches: by a seller's
request, or when staff book stock for a merchant (`Inventory::ReceiveStockService`; identity must know the
owner, or `422 UNKNOWN_MERCHANT`). gRPC only looks rows up, so stock booked for a merchant can be reserved
by order at once. gRPC never asks about standing: new sales stop at order's checkout.

## Stock writes

`merchant_principal_id` must be a UUID and is stored lower-case (Postgres returns `uuid` lower-case, and
a raw upper-case comparison read as another owner). A receipt's or adjustment's idempotency key is one
merchant's; the same key with a different body is `409 IDEMPOTENCY_KEY_CONFLICT`, and a replay reports the
original's bin.

One `bin_inventories` row per bin and SKU (unique index). The first receipt of a SKU into a bin inserts
the row with `ON CONFLICT DO NOTHING` and then locks it, so two first receipts at once land on one row.
The migration that added the index merged same-owner duplicates (quantities summed, reservations
re-pointed) and refuses to run while rows of one bin and SKU disagree about the owner.

`CheckBinStock`'s `low_stock_warning` compares the bin's available units with
`WAREHOUSE_LOW_STOCK_THRESHOLD` (required): how much warning is enough depends on how fast a store
sells, so it is an operating setting, not a rule of the contract. No service reads the flag today.

## The packing clock

`cutoff_hour` is an hour on the platform's clock, `KINETIX_TIME_ZONE` (IANA name, required, checked at
boot by `Kinetix::PlatformTimeZone`). Only the cutoff is computed on it; times are stored and rendered in
UTC as before.

The column is `NOT NULL DEFAULT 12` with a 0..23 check: a merchant projected from identity packs
against noon until it sets its own hour. The default lives in the schema only; the code reads the
column and has no fallback of its own (it had `|| 12`, which was the value every projected row used).

## Labels and the queue

`shipping_labels.print_count` counts prints; `reprint_count` is prints after the first. The queue is the
work left: tasks to pack, and packed tasks whose label has not been printed.

## Identity's signing keys

`Kinetix::TokenVerifier` answers a token's `kid` from the keys it holds. A `kid` it does not hold makes it fetch
identity's JWKS again only if the last fetch was at least `UNKNOWN_KEY_REFRESH_SECONDS` (ten) ago, one fetch at a
time. Until 2026-10-19 every request with an unknown `kid` fetched the JWKS, so forged tokens with made-up key ids
made identity answer once per request. A JWKS that cannot be fetched is `KeysUnavailable`, answered `503
IDENTITY_UNAVAILABLE`; it used to escape as a 500, and it is never a `401`, which would tell a signed-in user
their token is bad when identity simply did not answer.

## Type checking

`bundle exec srb tc` is at 0 errors since 2026-10-21. The task and order service stubs reach the
kinetix-contracts RBI through `sorbet/tapioca/require.rb` (tapioca does not load `*_services_pb` on its
own); `sorbet/rbi/todo.rbi` is `bin/tapioca todo` output. After a migration, regenerate the model's RBI
with `bin/tapioca dsl <Model> --environment test`. Neither CI runs Sorbet, so run it before a release.
