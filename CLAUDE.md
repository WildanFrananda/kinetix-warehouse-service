# CLAUDE.md — kinetix-warehouse-service

`AGENTS.md` holds the stack and the verification commands. This file holds decisions that the code
states but cannot explain.

## Fulfillment task status

`Fulfillment::TaskTransitions` is the whole rule. A merchant moves a task forward only —
`received → packing → packed` — and may set `packed` again, which re-sends the report to order when
the first one did not get through. Scanning takes the same steps.

`cancelled` is not a merchant's to set or to leave. Order cancels a task after it has released the
stock and refunded the buyer; a merchant reaching `cancelled` would leave order waiting on a parcel,
and a merchant leaving it would send order a "packed" report for an order the buyer has been
refunded for. Order refuses such a report too (it accepts "packed" only for a paid order of the same
merchant), but the warehouse does not send it in the first place.

`FulfillmentTaskRepository#update_status` takes `from:` so a move happens only if the task is still
where the caller read it; two requests racing on one task cannot both move it.

## Merchant standing

A principal becomes a merchant here once: `Merchants::ResolveService` asks identity whether it may
sell the first time it is seen, and keeps the local row after that. A merchant suspended later can
still pack, label and process returns for orders that were already paid — the buyer has paid and the
parcel should still go. New sales are stopped where money moves: order refuses a checkout for a
merchant identity says may not sell.

## Type checking

`bundle exec srb tc` reported 34 errors on `main` at v0.1.18 (stale generated RBIs for the order and
fulfillment protos, and redundant `T.must`s). Neither CI runs Sorbet. Do not add to the count; a
change is checked by comparing the total before and after.
