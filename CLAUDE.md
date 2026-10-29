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

Order's gRPC status decides the answer (2026-10-27, `Order::GrpcClient#ask`): unreachable, `UNAVAILABLE`,
`RESOURCE_EXHAUSTED` are `503 ORDER_UNAVAILABLE` (the call did not reach order: nothing recorded);
`DEADLINE_EXCEEDED` is `503 ORDER_TIMEOUT` (order may have recorded it; the client repeats the request, which
order answers once and then with `already_open` / `already_recorded`); `NOT_FOUND` `404 ORDER_NOT_FOUND`;
`INVALID_ARGUMENT` `422 ORDER_INVALID_REQUEST`; `FAILED_PRECONDITION`/`ALREADY_EXISTS` `409 ORDER_CONFLICT`
(the stock routes' status for a state conflict); the rest, and an answer holding a NUL, `502 ORDER_FAILED`,
all in fixed words. `PERMISSION_DENIED` is `502`, not `403`: at order v1.4.3 it comes only from order's mesh
allow list refusing warehouse itself, which the seller cannot fix; order's business refusals arrive in the
answer's `error`, as `RETURN_NOT_RECORDED`.

`cancelled` is not a merchant's to set or to leave. Order cancels a task after it has released the
stock and refunded the buyer; a merchant reaching `cancelled` would leave order waiting on a parcel,
and a merchant leaving it would send order a "packed" report for an order the buyer has been
refunded for. Order refuses such a report too (it accepts "packed" only for a paid order of the same
merchant), but the warehouse does not send it in the first place.

`FulfillmentTaskRepository#update_status` takes `from:` so a move happens only if the task is still
where the caller read it; two requests racing on one task cannot both move it.

## Packing needs every line scanned

The user's ruling of 2026-10-22: a task becomes `packed` only when every line has been matched by a scan;
a scan that matches nothing is refused; a scan of a line already matched is idempotent. A line remembers
its scan in `fulfillment_task_lines.scanned_at`, set once by a conditional update, so two scans of one
line count once. `AdvanceTaskService` refuses `packing → packed` while a line is unscanned, so setting the
status by hand cannot skip the scans either; `packed → packed` (the re-send) is not checked.

A scan (`VerifyScanService`) matches a line's SKU first, then the order number, then the tracking number;
only a SKU marks a line (an unscanned one first, when two lines share a SKU), so the paperwork's numbers
start packing a `received` task and never pack one. After marking it counts the lines left and walks
`TaskTransitions.steps_on_scan`. A step another request already took is not an error: the task is re-read
and the scan answers where it is now, and only the request whose step to `packed` succeeded tells order. A
scan of a `packed` parcel changes nothing and reports nothing to order, unlike before 2026-10-22; the status
route is the re-send. The answer names what matched (`matched`: `sku` / `order_number` /
`tracking_number`, and `matched_code`), keeps `matched_sku` for a SKU only, and says `lines_remaining`.
Tasks packed before the column existed have unscanned lines; nothing back-fills them, because nobody knows
whether they were scanned.

## Returns

A return is order's record; warehouse relays it (`Order::ReturnRelay`) and keeps nothing. Returned goods are
not booked back into stock automatically: the relay of goods received tells order only, and staff book
what is fit to sell with a stock receipt (the coordinator's decision of 2026-10-22). A return is opened by
task id, and a task leaves the queue once its label is printed, so `GET /fulfillment_tasks?order_number=`
finds the caller's own task for an order whatever its state, cancelled and printed included. It is the
merchant's, as opening a return is: identity must know the merchant, nothing more.

What is relayed is checked first (2026-10-27): a `return_number` not in order's format
(`RMA-<yyyymmdd>-<8 upper-case hex>`) is `404 Return not found`; a reason over 500 UTF-16 units (order's
column, which order would cut) or a returned SKU over 128 is `422`; whitespace-only values are refused by
Unicode's rule, as order's `IsNullOrWhiteSpace` reads them. No `bin_code` is relayed as `nil`, the field left
unset; contract v1.7.0's `string bin_code` has no presence, so order still reads `""` and stores `NULL`.

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

Numbers in a request are read by `Kinetix::IntegerParam`: a JSON integer, or a string of ASCII digits (a
sign only where a sign makes sense, the delta). `true`, `2.9`, `"12abc"`, `"0x10"` and `" 5"` are refused,
not truncated as `to_i` did. Every count is an `integer` column, so ranges stop at 2,147,483,647: a
quantity is 1 to that, a delta is non-zero within int32, a shelf level is 0 to that, and a receipt or
adjustment that would take a bin's quantity past it is `422 STOCK_LIMIT_EXCEEDED` inside the transaction,
before anything is written. A key longer than the ledger's `varchar(255)` is `422 INVALID_IDEMPOTENCY_KEY`
before the write. Returned lines are int32 in order's contract and use the same reader.

One `bin_inventories` row per bin and SKU (unique index). The first receipt of a SKU into a bin inserts
the row with `ON CONFLICT DO NOTHING` and then locks it, so two first receipts at once land on one row.
The migration that added the index merged same-owner duplicates (quantities summed, reservations
re-pointed) and refuses to run while rows of one bin and SKU disagree about the owner.

`CheckBinStock`'s `low_stock_warning` compares the bin's available units with
`WAREHOUSE_LOW_STOCK_THRESHOLD` (required): how much warning is enough depends on how fast a store
sells, so it is an operating setting, not a rule of the contract. No service reads the flag today.

## Ids, strings and lengths in a request

A task or merchant id in a path is read by `Kinetix::IntegerParam.id`: ASCII digits only, 1 to the bigint
maximum, leading zeros allowed (`012` is task 12). Anything else names no record and is `404` (`Fulfillment task
not found`, `Merchant not found`), checked after the caller's standing and before anything else; `to_i` read
`/12abc`, `/+12`, `/12%20` and `/1e3` as an id and acted on that task. On `PATCH /merchants/{id}` an id in digits
that is not the caller's stays `403`. The task ids order sends to `CancelFulfillmentTask` and `RecordCourierAwb`
use the same reader (`UNKNOWN_TASK` otherwise): `Integer()` took `0x10`, `010` (octal, task 8) and ` 12 `.

A string field is used only if it arrives as a JSON string (`ApiStringParams#refuse_unusable_strings`, before
anything is read or written). Another JSON type, or a string holding a NUL, is `422`: `INVALID_<FIELD>` with a
`message` on the stock routes, `{ error: "<field> must be a string" }` on the others, a line's sku in returned
goods with the form's own sentence. `to_s` made `["A"]` the bin code `["A"]` and relayed an array's inspect
string to order as a return reason; Postgres cannot store a NUL, and pg raised `ArgumentError`, a `500`. A
`merchant_principal_id` of another JSON type is `422 INVALID_MERCHANT_PRINCIPAL_ID`, while a string that is not
a UUID stays `400` as before. `GET /fulfillment_tasks?order_number=` is a query, and stays `400` for anything
but one string.

A scanned code is at most 128 characters, the longest SKU, else `422` before matching (2026-10-27); it is
never stored.

A bin code is at most 64 characters, a zone 64, a receipt's or adjustment's note 1000: room for any code a
label printer prints and a paragraph of explanation. They are `varchar(n)` since migration 20261022184035, so
no path writes more; Postgres and Ruby both count characters, not bytes. The code checks first: a bin's
validation (`422`, the route's sentence), `INVALID_BIN_CODE` / `INVALID_NOTE` on the stock routes, and a
returned-goods `bin_code` over 64 before order is told. The migration refuses, naming each row's id and length,
when a value is longer; it never shortens one. Before deploying it, run on production (read-only):

```sql
SELECT 'warehouse_bins.bin_code' AS field, max(char_length(bin_code)) AS longest,
       count(*) FILTER (WHERE char_length(bin_code) > 64) AS over_limit FROM warehouse_bins
UNION ALL
SELECT 'warehouse_bins.zone', max(char_length(zone)), count(*) FILTER (WHERE char_length(zone) > 64)
FROM warehouse_bins
UNION ALL
SELECT 'stock_receipts.note', max(char_length(note)), count(*) FILTER (WHERE char_length(note) > 1000)
FROM stock_receipts
UNION ALL
SELECT 'stock_adjustments.note', max(char_length(note)), count(*) FILTER (WHERE char_length(note) > 1000)
FROM stock_adjustments;
```

## Strings over gRPC

`Kinetix::NulRefusalInterceptor`, innermost in `GrpcServer` (after the allow list), answers a request with a
NUL in any string field `INVALID_ARGUMENT "<field> must not contain a NUL character"` (2026-10-27); pg used to
raise and Ruby gRPC sent `UNKNOWN` with the exception's text. `bytes` fields, binary in Ruby, are left alone.

A string from order that reaches the database is length-checked first (`Rpc::StringLimits`, `INVALID_ARGUMENT
"<field> must be at most N characters"`): an order number 64, a SKU 128 (the stock ledger's limits), a
tracking number 64 (order's `awb_number` column). Their columns stay unbounded: gRPC is their only writer. A
principal or task id never reaches the database unless it is a UUID or digits, and `ReserveStock` /
`ReleaseStock` keep their own `INVALID_ARGUMENT` refusals in the answer.

No gRPC error carries an exception's text (2026-10-27). `Kinetix::ErrorStatusInterceptor`, inside the request
id interceptor, passes a deliberate status through and turns anything else into `UNAVAILABLE "warehouse could
not reach its database; try again shortly"` (a `Kinetix::DatabaseOutage`) or `INTERNAL "warehouse failed while
handling this call"`, logging the exception under the request id. Ruby gRPC used to send `UNKNOWN "<class>:
<message>"`, the database's host name included. `AWB_REFUSED` says `that tracking number is already on another
parcel` instead of the validation message.

## The database unreachable

A request that cannot reach Postgres is `503 DATABASE_UNAVAILABLE`, `Retry-After: 15`, as in catalog, order
and review (2026-10-27); `Kinetix::DatabaseOutage` counts connection failures only (a full pool included),
so a query error stays `500`. The message does not claim nothing was written: a commit may have landed.

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

## Admin audit

Every admin action over HTTP (bin upsert, stock receipt, stock adjustment; the only admin-only writes) runs
inside `ApiAdminAudit#audit_admin_action`, after `require_staff!`, so a non-admin turned away is not an
admin action. Once the action has answered, one INFO line `admin_action actor=<sub> action=<action>
target="<bin>/<sku>" outcome=<outcome> request_id=<id>` is logged and `kinetix_admin_actions_total{action,
outcome}` counted: 2xx is `done`, 4xx `refused`, anything else `failed`. A raise is handed to the
controller's own `rescue_from` handler first, so the outcome is the status the client got (an unreadable
body is `refused`, identity down is `failed`). The target is JSON-quoted, so a bin code cannot forge the
fields after it. The counter is pre-published at zero for every action and outcome by the metrics
initializer, in both processes, as the gRPC client series are. gRPC calls are not audited.

## Stock reads

The backoffice reads stock through four admin-only `GET`s (2026-10-29): `/bins` (each bin with
`sku_count`, the SKUs holding at least one unit, and the units of every SKU together), `/bins/stock` (one
row per bin and SKU, rows at zero included), `/stock_receipts` and `/stock_adjustments` (the ledger,
newest first). They are reads, not admin actions, so `audit_admin_action` does not wrap them. They live
under the three paths the gateway already routes through its staff gate (`warehouse-bins-staff-route` and
the two stock routes match by prefix), so no gateway change was needed; a new top-level path would have
gone through the open `warehouse-route` instead.

Paging is keyset, never offset: bins by `bin_code` (`after`, answered `next_after`), stock rows by id
ascending (`after`, `next_after_id`), the ledger by id descending (`before`, `next_before_id`).
`Inventory::Page` asks the repository for one row more than the limit, so the cursor is null exactly when
the page is the last, a full last page included. The filters (`sku`, `bin_code`, `merchant_principal_id`)
combine and are exact. A query parameter that cannot be read is `400 INVALID_<PARAMETER>` with a
`message`, raised as `ApiLedgerQuery::BadQuery` and rendered by its own `rescue_from`, after the caller's
role is checked: an array (`sku[]=`), an empty or over-long string, a NUL, a merchant that is no UUID, a
cursor or limit not in digits. The limit is 1 to 100, 50 when absent.

## Identity's signing keys

`Kinetix::TokenVerifier` answers a token's `kid` from the keys it holds. A `kid` it does not hold makes it fetch
identity's JWKS again only if the last fetch was at least `UNKNOWN_KEY_REFRESH_SECONDS` (ten) ago, one fetch at a
time. Until 2026-10-19 every request with an unknown `kid` fetched the JWKS, so forged tokens with made-up key ids
made identity answer once per request. A JWKS that cannot be fetched is `KeysUnavailable`, answered `503
IDENTITY_UNAVAILABLE`; it used to escape as a 500, and it is never a `401`, which would tell a signed-in user
their token is bad when identity simply did not answer.

## Tests

The suite passes in random order (checked 2026-10-27 with eight seeds; `.rspec` and both CIs still run in
defined order). A spec that runs a migration inside its example includes the shared context `a migration runs
inside each example`, which resets the models' column information before and after: a column type changed
under the test transaction left prepared statements whose result type no longer matched, and the next example
to reuse one failed with `PreparedStatementCacheExpired`.

## Type checking

`bundle exec srb tc` is at 0 errors since 2026-10-21. The task and order service stubs reach the
kinetix-contracts RBI through `sorbet/tapioca/require.rb` (tapioca does not load `*_services_pb` on its
own); `sorbet/rbi/todo.rbi` is `bin/tapioca todo` output. After a migration, regenerate the model's RBI
with `bin/tapioca dsl <Model> --environment test`. Neither CI runs Sorbet, so run it before a release.
