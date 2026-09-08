# Stock idempotency runbook

What warehouse did for an order, and whether it did anything twice. Everything here is answerable
with `psql` alone.

## The two tables, and why there are two

`stock_reservations` is the ledger: one row per `(merchant_id, order_number, sku)`,
`released_at IS NULL` means held. It is business state and is **never pruned**. A zero-quantity row
with `released_at` set is a *tombstone* — a release that arrived before the reserve it was undoing.
It is what makes a released pair terminal, so deleting one re-opens the leak it was written to
close.

The uniqueness is scoped to the merchant, not global. That grain matters in both directions: a
reserve and the release compensating it always carry the same `merchant_principal_id`, so they
still collide on this index and one still blocks on the other's uncommitted tuple — which is the
whole mechanism. Two *different* merchants were never in that race, and while the index was global,
one merchant sending a stray `ReleaseStock` wrote a tombstone that permanently denied another
merchant an order number it had never used.

`stock_operations` is the replay cache: one row per completed reserve or release attempt, holding
the serialized reply in `response`. Unique on `(merchant_id, operation, idempotency_key)` — scoped
to the merchant for the same reason the ledger is. Most callers send no key, so the gate derives
`"#{operation}:#{order_number}:#{sku}"`, which has no tenant in it; while that index was global the
first merchant to use a pair claimed the key estate-wide and the second was refused
`IDEMPOTENCY_KEY_CONFLICT` on its own compensation, with the stock left held.

The operations table deduplicates an identical **attempt** and can reproduce its reply byte for
byte. The ledger deduplicates the **effect** across distinct attempts. Neither subsumes the other,
which is why pruning the first is safe and pruning the second is not.

### Retention, as it actually is

`PruneStockOperationsJob` drops `stock_operations` rows older than seven days, except rows with
`conflict_count > 0`. It is scheduled in `config/recurring.yml` under `production:`.

**That schedule does not currently run.** Recurring entries are executed by a solid_queue
*supervisor* process; `kinetix-infrastructure/compose.yaml` deploys only `kinetix-warehouse-service`
(whose CMD is `./bin/thrust ./bin/rails server`) and `kinetix-warehouse-grpc`. There is no
supervisor anywhere, so **retention is infinite today**: every reserve and release attempt ever
made is still in the table. Do not reason "the row is missing, so it was pruned" — if a row is
missing, it was never written.

The same is true of `ReportAbandonedHoldsJob` below. Until a `bin/rails solid_queue:start`
container is added to compose.yaml and the production manifest — infrastructure work, not this
repository's — drive both from cron:

```
bin/rails runner 'PruneStockOperationsJob.perform_now'
bin/rails stock:abandoned_holds
```

## Log anchors

All prefixed `stock.idem`, all carrying `request_id=` in the message body — `config.log_tags` is an
ActionDispatch tag and gRPC never traverses Rack, so it is empty for every call here.

| Anchor | Level | Means |
| --- | --- | --- |
| `stock.idem replay` | WARN | A duplicate was answered from stored bytes. Correct, but never normal at steady state. |
| `stock.idem replay_refused` | ERROR | A duplicate could NOT be answered: the stored reply was a reserve success and the ledger has since let that stock go. The caller was refused `STOCK_RESERVATION_RELEASED`. See query 6. |
| `stock.idem conflict` | ERROR | One key was reused for a different request. A caller has a bug. |
| `stock.idem retry_later` | ERROR | A wait ran out. `error_code=` says which wait — see "The one knob". |
| `stock.idem refused` | WARN | The work ran and declined. `error_code=` says why. Nothing was recorded. |
| `stock.idem orphan_release` | ERROR | A release found nothing to release and wrote a tombstone. Its reserve is late, lost, or never happened. |
| `stock.idem release_bin_missing` | ERROR | The bin a reservation debited has been retired. Nothing left to credit. |
| `stock.idem release_bin_guessed` | ERROR | A release had to guess which bin to credit, because the ledger row predates `bin_inventory_id`. `wanted=` vs `credited=` says how much of the hold went back; any shortfall is stranded on another bin and query 2 will show it. Expect this only for rows written before 2026-09-08; a steady stream means something is writing ledger rows without a bin. |
| `stock.idem abandoned_hold` | ERROR | Stock has been held with no release for longer than the threshold. **This is the one that means units are frozen.** See "A hold nobody is coming back for". |
| `stock.idem abandoned_hold_summary` | INFO / ERROR | The report ran. INFO when it found nothing, ERROR when it did. Its absence means the report is not running at all. |
| `stock.idem operator_release` | WARN | `rake stock:release_hold` finished. `credited=` says whether any counter actually moved and `already_released_by_a_caller=` whether a caller won the row first — read both before recording that units were recovered. Always expect a paired `abandoned_hold` before it. |
| `stock.idem lock_timeout_under_deadline` | WARN | `WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS` is configured below the caller's assumed deadline. Said once per process. Should never appear outside tests. |

## The one knob

`WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS` (default 15, clamped to 1–120) bounds how long a call waits
on a row another transaction is holding.

**It must stay above the calling service's gRPC deadline.** order-service defaults
`KINETIX_GRPC_DEADLINE_SECONDS` to 5; warehouse cannot read that value at runtime, so it restates it
as `Inventory::IdempotentOperation::ASSUMED_CALLER_DEADLINE_SECONDS` and logs
`stock.idem lock_timeout_under_deadline` once if you configure the wait below it. If a caller ever
raises its deadline past 15s, raise this knob too.

The reason is warehouse-local, and it is not a claim about what the caller does with a refusal.
This wire has no "retry me": both replies carry only `success: false` plus an `error_code`, and
nothing in the contract distinguishes "try again in a moment" from "this will never work". Whether
a caller retries, gives up, or compensates is that caller's policy — warehouse cannot observe it and
must not assume it. (An earlier version of this section did assume it, stating that a refusal parked
the saga in `Stuck` where its sweeper never looked again. That was untrue when written, and
order-service's sweeper has changed again since. Anything asserted here about another service's
control flow is a liability, not a justification.)

So the design does not depend on the caller's reaction; it makes the answer it cannot predict rare.
While the wait outlasts the caller's deadline, the ordinary lost-duplicate case ends with the caller
timing out first while warehouse finishes and commits the right thing, and no refusal is emitted at
all. Lower the wait below the deadline and the ordering inverts: warehouse starts answering first,
with the one answer whose handling it does not control — and a release that gives up waiting for the
reserve it must tombstone is exactly the leak the tombstone exists to prevent.

Raise it if `stock.idem retry_later` appears at all; never lower it to make a slow reserve look
faster.

`retry_later` carries one of three error codes. They name three different waits, and the point of
having three is that each one is TRUE of the statement that actually timed out.

| `error_code` | The wait was on | Do |
| --- | --- | --- |
| `RESERVATION_IN_PROGRESS` | a **duplicate of this same request** — another connection holds an uncommitted `stock_operations` row under the same `(merchant_id, operation, idempotency_key)`. | Look for a caller retrying inside its own deadline, or for a reserve slow enough to be worth profiling. |
| `STOCK_LEDGER_BUSY` | **another call for this same order and sku** — the `stock_reservations` row for this `(merchant_id, order_number, sku)`. Almost always the reserve this release is compensating, still uncommitted. | Expected under load and NOT a caller bug. Look at how long reserves are taking; the pair resolves itself as soon as the other side commits. |
| `STOCK_LOCK_TIMEOUT` | **a different order** — one of the sku's `bin_inventories` rows, held by a transaction working on some other order. | Look at what else is contending for that sku. There is no duplicate; the caller that got this message has no bug. |

Why three and not two. The ledger wait and the bin wait were collapsed into `STOCK_LOCK_TIMEOUT`
and this table used to say that code meant "a different order — the ledger row for this pair, or one
of the sku's bin rows". The first half of that was false, and false about the design's most common
contention: the saga compensates steps that are still `Attempting`, so a `ReleaseStock` arriving
behind its own uncommitted `ReserveStock` is the routine case. Measured on this database with
`log_statement=all`, an in-flight reserve for `(ORD-2, SKU-RACE)` and a compensating release for the
same pair one second behind it:

```
ERROR:  canceling statement due to lock timeout
STATEMENT:  INSERT INTO "stock_reservations" ("bin_inventory_id", "created_at", "merchant_id", ...
```

and `pg_blocking_pids` reported that INSERT waiting on a `ShareLock` on the **reserve's own
transactionid** — same merchant, same order_number, same sku. The operator was being told "another
order is holding this sku's rows" and sent to look at a sku nobody else was touching.

All three are checked rather than asserted. `spec/rpc/bin_stock_service_concurrency_spec.rb` drives
each wait against a real second connection and asserts its code, so a future change that folds two
of them back together fails there.

## The queries

**1. The double-reserve invariant. Alert on any row.**

```sql
SELECT merchant_id, order_number, sku, count(*)
FROM stock_operations
WHERE operation = 'reserve' AND applied
GROUP BY merchant_id, order_number, sku
HAVING count(*) > 1;
```

Two reserve operations that each MOVED the counter for one `(merchant_id, order_number, sku)` should
be impossible: a second attempt is either replayed from the first's row, absorbed by the held ledger
row, or refused as terminal. A row here means the dedupe did not hold, or the prune removed the
first row and a very late duplicate then re-did the work.

`merchant_id` is in the grouping because it is in the ledger's unique index. Two *different*
merchants each holding their own `(ORD-X, SKU-Y)` is legitimate — order numbers are the caller's
namespace and SKUs are the merchant's, so nothing stops them colliding — and grouping without
`merchant_id` reports that correct state as a double reserve.

`AND applied` is load-bearing, not a filter for tidiness. Two committed reserve *rows* for one pair
are legitimate — a caller that sends a second distinct key against a hold that already exists gets
`success: true` without taking stock twice, and that commits a second row. Counting rows instead of
applications makes this alert fire on correct behaviour, and an alert that cries wolf gets switched
off. Use `applied` for "did stock move twice", and drop it only when the question is "how many
attempts arrived", which is query 3.

**2. Physical reconciliation — the only query that catches a counter that drifted with no ledger
row behind it.** This finds leaks that predate the idempotency work.

```sql
SELECT b.id, b.sku, b.reserved_quantity, COALESCE(SUM(r.quantity), 0) AS ledger_held
FROM bin_inventories b
LEFT JOIN stock_reservations r
  ON r.bin_inventory_id = b.id AND r.released_at IS NULL
GROUP BY b.id, b.sku, b.reserved_quantity
HAVING b.reserved_quantity <> COALESCE(SUM(r.quantity), 0);
```

Reservations written before `bin_inventory_id` existed carry NULL there and will show as drift on
their bin; check `WHERE bin_inventory_id IS NULL AND released_at IS NULL` before acting.

**This query cannot find an abandoned hold.** It compares warehouse against itself, and an abandoned
hold has no drift — the counter and the ledger agree exactly, and they are both wrong about the
world. Query 8 is the one that finds those.

**3. Everything warehouse did for one order.**

```sql
SELECT merchant_id, operation, idempotency_key, quantity, replay_count, replay_refused_count,
       conflict_count, first_request_id, last_replay_request_id, created_at
FROM stock_operations
WHERE order_number = :order_number
ORDER BY created_at;
```

`merchant_id` is selected, not filtered on: an order number is not unique across merchants, so read
the column before concluding that two rows are two attempts at the same thing.

**4. What that order holds right now.**

```sql
SELECT merchant_id, sku, quantity, bin_inventory_id, released_at
FROM stock_reservations
WHERE order_number = :order_number;
```

`quantity = 0` with `released_at` set is a tombstone: nothing was ever held under that pair.

**5. Duplicates that actually fired, most recent first.**

```sql
SELECT operation, order_number, sku, replay_count, last_replay_request_id, updated_at
FROM stock_operations
WHERE replay_count > 0
ORDER BY updated_at DESC
LIMIT 50;
```

`replay_count` counts only duplicates that were SERVED the stored bytes. A duplicate that had to be
refused is in `replay_refused_count` instead, which is query 6 — it used to be counted here, so this
query reported refusals as though they had been served.

**6. Duplicates that had to be refused.**

```sql
SELECT operation, order_number, sku, replay_refused_count, last_replay_request_id, updated_at
FROM stock_operations
WHERE replay_refused_count > 0
ORDER BY updated_at DESC;
```

A reserve whose stored reply was a success, arriving again after the ledger released that stock. The
refusal is correct and is the single most important behaviour in this design: replaying the stored
success would let the caller's saga mark its reserve step Done and go on to take money against a
hold nobody holds. Its presence means a duplicate reserve is arriving after its own compensation —
look at the caller's deadline against how long `ReserveStock` actually takes.

**7. Caller bugs. These rows are never pruned.**

```sql
SELECT merchant_id, operation, idempotency_key, order_number, sku, conflict_count, created_at
FROM stock_operations
WHERE conflict_count > 0
ORDER BY conflict_count DESC;
```

A conflict means one merchant sent one key for two different requests. Nothing was mutated in either
direction — find the caller. `merchant_id` names it: keys are scoped per merchant, so two merchants
using the same key string is not a conflict and never produces a row here.

**8. Stock held by nobody. Alert on any row.**

```sql
SELECT id, merchant_id, order_number, sku, quantity, bin_inventory_id, created_at,
       now() - created_at AS held_for
FROM stock_reservations
WHERE released_at IS NULL
  AND created_at < now() - interval '24 hours'
ORDER BY created_at;
```

Same threshold as `Inventory::AbandonedHoldReport` (`WAREHOUSE_ABANDONED_HOLD_HOURS`, default 24).
`bin/rails stock:abandoned_holds` prints the same rows and writes the `stock.idem abandoned_hold`
anchors. Read the next section before acting on a row here.

**9. Tombstones, i.e. releases that outran their reserves.**

```sql
SELECT merchant_id, order_number, sku, created_at
FROM stock_reservations
WHERE quantity = 0 AND released_at IS NOT NULL
ORDER BY created_at DESC;
```

A steady trickle is the compensation path working as designed. A spike means reserves are timing
out — check the caller's gRPC deadline against how long `ReserveStock` is actually taking.

## A hold nobody is coming back for

This is the one way stock is still lost, and it is a real path rather than a theoretical one.

A reserve commits and holds N units. The reply never reaches the caller — its deadline fires, or the
connection drops. The caller compensates, and every `ReleaseStock` is refused or times out. Every
caller's retry budget is finite, so eventually it stops. From that moment
`bin_inventories.reserved_quantity` stays `+N` and `stock_reservations.released_at` stays NULL
forever. Nothing in warehouse expires a held row, and nothing outside it will call again. Those
units are unsellable and query 2 will never report them, because warehouse is perfectly consistent
with itself about a hold that no longer corresponds to anything real.

**What warehouse does about it:** reports, and does not reap.

`Inventory::AbandonedHoldReport` names every hold older than the threshold, one
`stock.idem abandoned_hold` per row at ERROR plus a summary. Alert on that anchor. That is the whole
automatic behaviour — it writes nothing.

**Why there is no reaper.** Warehouse cannot tell "the owner gave up" from "the owner is slow". Both
look identical from here: a held row and no further calls. They want opposite actions, and they are
not equally bad if you get them wrong — releasing a hold whose order is still live sells the same
units twice, and overselling is worse than holding. The decision needs somebody who can read the
other side's saga state, so it is a command a human runs, not a timer.

**Reclaiming one, once you have confirmed in order-service that the order is dead:**

```
bin/rails 'stock:release_hold[RESERVATION_ID]'
```

The id comes from query 8 or from `bin/rails stock:abandoned_holds`. It runs the ordinary
`Inventory::ReleaseStockService` — the same credit, the same lock order, the same handling of a bin
that has since been retired — and logs `stock.idem operator_release`.

**Read what it printed; it does not always mean units came back.** Two of its three endings reclaim
nothing, and both are normal:

* *"a caller got there first"* — the owning saga's own `ReleaseStock` committed while this command
  was waiting on the row lock. The units are back, but a caller returned them, not you. Nothing was
  credited twice; the reclaim blocks on the ledger row's `FOR UPDATE` and then sees the closed row.
* *"WITHOUT crediting any counter"* — the ledger row was closed but no counter moved, because the
  bin it debited is gone or could not be identified. Read the `stock.idem release_bin_missing` or
  `release_bin_guessed` line logged immediately before it. **Those units are not back on the shelf**
  and query 2 is where the shortfall now shows.

**Why this does not re-open the race the tombstone closes.** That race is closed by the EXISTENCE of
a row for `(merchant_id, order_number, sku)`: a late reserve either collides with it on the unique
index or reads it and is refused `STOCK_RESERVATION_RELEASED`. Reclaiming sets `released_at` and
**keeps the row**. Nothing here deletes a ledger row — not the report, not the operator task, not
the prune, which touches `stock_operations` only. A reclaimed hold is terminal for a late reserve in
exactly the way a tombstone is; the only thing that changed is that the units went back on the
shelf.

## What this cannot tell you

Warehouse cannot report "that reserve was a duplicate" on the wire: `ReserveStockResponse` has no
`already_*` field and adding one would mean a contract version bump published to five ecosystems
and consumed by eight services, to populate a property order-service reads nowhere. A byte-identical
replay is strictly stronger for a retrying caller, but a caller doing reconciliation against its own
records has no signal, so **duplicate reserves live only in warehouse's logs and this table, never
in order-service's saga step table**. Post-incident reconstruction from the order side stays blind
to them. If duplicates turn out to be frequent, that decision needs revisiting.

Warehouse also cannot tell you what the caller did next with a refusal, and nothing in this document
should be read as saying it can. What happens to a saga after `RESERVATION_IN_PROGRESS`,
`STOCK_LEDGER_BUSY` or `STOCK_LOCK_TIMEOUT` — retried, compensated, abandoned — is order-service's
behaviour, is
configurable there, and has changed more than once. Diagnose from the anchors above and from
order-service's own saga tables, not from an assumption recorded here.
