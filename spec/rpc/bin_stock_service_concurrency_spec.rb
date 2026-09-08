# typed: false
# frozen_string_literal: true

require "rails_helper"
require "fulfillment/v1/fulfillment_services_pb"
require_relative "../../app/rpc/bin_stock_service_handler"

RSpec.describe "Rpc::BinStockServiceHandler across two connections" do
  self.use_transactional_tests = false

  let(:handler) { Rpc::BinStockServiceHandler.new }
  let(:principal) { "dddddddd-1111-2222-3333-444444444444" }
  let(:other_principal) { "dddddddd-9999-2222-3333-444444444444" }

  SETTLE = 0.5

  def wipe
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '10s'")
      StockOperation.delete_all
      StockReservation.delete_all
      BinInventory.delete_all
      WarehouseBin.delete_all
      Merchant.where(code: [ "BIN-CONC", "BIN-CONC2" ]).delete_all
    end
  end

  before do
    @threads = []
    @gates = []
    wipe
    @merchant = Merchant.create!(
      name: "Concurrency Merchant", code: "BIN-CONC", cutoff_hour: 14, principal_id: principal
    )
    @other_merchant = Merchant.create!(
      name: "Other Concurrency Merchant", code: "BIN-CONC2", cutoff_hour: 14,
      principal_id: other_principal
    )
    @bin = WarehouseBin.create!(bin_code: "C-01", zone: "C", shelf_level: 1)
    @inventory = BinInventory.create!(
      warehouse_bin: @bin, sku: "SKU-C", quantity: 10, reserved_quantity: 0
    )
  end

  after do
    release
    wipe
  end

  def release
    @gates.each { |gate| gate << :release }
    @threads.each { |thread| thread.join(5) }
  end

  def reserve_request(order_number: "ORD-C", key: nil, quantity: 3, principal_id: principal)
    Fulfillment::V1::ReserveStockRequest.new(
      merchant_principal_id: principal_id, sku: "SKU-C", quantity: quantity,
      order_number: order_number,
      idempotency_key: key ? Common::V1::IdempotencyKey.new(key: key) : nil
    )
  end

  def release_request(order_number: "ORD-C", key: nil, principal_id: principal)
    Fulfillment::V1::ReleaseStockRequest.new(
      merchant_principal_id: principal_id, sku: "SKU-C", quantity: 3, order_number: order_number,
      idempotency_key: key ? Common::V1::IdempotencyKey.new(key: key) : nil
    )
  end

  def in_flight(result_queue)
    gate = Queue.new
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          result_queue << yield
          gate.pop
        end
      end
    end
    @threads << thread
    @gates << gate
    [ thread, gate ]
  end

  def on_own_connection(&blk)
    thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection(&blk) }
    @threads << thread
    thread
  end

  def reserved_quantity
    BinInventory.find(@inventory.id).reserved_quantity
  end

  it "blocks a duplicate on the unique index and replays the winner's exact bytes" do
    results = Queue.new
    winner, gate = in_flight(results) { handler.reserve_stock(reserve_request(key: "K-1"), nil) }
    first = results.pop

    expect(first.success).to be(true)
    # Nothing of the winner's work is visible from this connection yet.
    expect(StockReservation.count).to eq(0)

    loser = on_own_connection { handler.reserve_stock(reserve_request(key: "K-1"), nil) }
    sleep SETTLE
    expect(loser.alive?).to be(true)

    gate << :commit
    winner.join
    second = loser.value

    expect(second.to_proto).to eq(first.to_proto)
    expect(StockReservation.count).to eq(1)
    expect(StockOperation.count).to eq(1)
    expect(StockOperation.first.replay_count).to eq(1)
    expect(reserved_quantity).to eq(3)
  end

  it "lets the duplicate do the work itself when the original rolls back" do
    results = Queue.new
    gate = Queue.new
    winner = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ActiveRecord::Base.transaction do
          handler.reserve_stock(reserve_request(key: "K-1"), nil)
          results << :reserved
          gate.pop
          raise ActiveRecord::Rollback
        end
      end
    end
    # Hand-rolled rather than #in_flight because this one must ROLL BACK, so register it by hand
    # too — otherwise a failure below leaves it holding a transaction and the wipe blocks on it.
    @threads << winner
    @gates << gate
    results.pop

    loser = on_own_connection { handler.reserve_stock(reserve_request(key: "K-1"), nil) }
    sleep SETTLE
    expect(loser.alive?).to be(true)

    gate << :abort
    winner.join
    res = loser.value

    expect(res.success).to be(true)
    expect(StockOperation.count).to eq(1)
    # It reserved for the first time rather than replaying: the winner left nothing behind.
    expect(StockOperation.first.replay_count).to eq(0)
    expect(StockReservation.count).to eq(1)
    expect(reserved_quantity).to eq(3)
  end

  it "does not let a reserve hold stock when the release compensating it arrived first" do
    # The dominant real duplicate in this estate: the saga compensates steps that are still
    # Attempting, and the 5s gRPC deadline makes a slow reserve routine, so a ReleaseStock can
    # reach warehouse BEFORE the ReserveStock it is undoing. Answering "already released" would
    # let the step be marked Compensated and then let the reserve land and hold stock forever.
    results = Queue.new
    reserver, gate = in_flight(results) { handler.reserve_stock(reserve_request, nil) }

    expect(results.pop.success).to be(true)
    expect(StockReservation.count).to eq(0)

    releaser = on_own_connection { handler.release_stock(release_request, nil) }
    sleep SETTLE
    # Blocked on the tombstone insert, not answering "already released" over an invisible reserve.
    expect(releaser.alive?).to be(true)

    gate << :commit
    reserver.join
    res = releaser.value

    expect(res.success).to be(true)
    expect(reserved_quantity).to eq(0)
    expect(StockReservation.find_by(order_number: "ORD-C").released_at).to be_present
  end

  it "makes a tombstone win when it commits first, so the late reserve holds nothing" do
    results = Queue.new
    releaser, gate = in_flight(results) { handler.release_stock(release_request, nil) }

    expect(results.pop.already_released).to be(true)

    reserver = on_own_connection { handler.reserve_stock(reserve_request, nil) }
    sleep SETTLE
    expect(reserver.alive?).to be(true)

    gate << :commit
    releaser.join
    res = reserver.value

    expect(res.success).to be(false)
    expect(res.error.error_code).to eq("STOCK_RESERVATION_RELEASED")
    expect(reserved_quantity).to eq(0)
  end

  it "waits for an in-flight release rather than deadlocking against it" do
    # Reserve used to lock bin_inventories first and stock_reservations second while release did
    # the opposite, so a reserve racing a release deadlocked and Postgres killed one of them.
    # Both now take the reservation row before the bin, which leaves no cycle to detect.
    handler.reserve_stock(reserve_request(order_number: "ORD-HELD"), nil)
    expect(reserved_quantity).to eq(3)

    results = Queue.new
    releaser, gate = in_flight(results) do
      handler.release_stock(release_request(order_number: "ORD-HELD"), nil)
    end
    expect(results.pop.success).to be(true)

    # A different order, the same sku: it needs the bin row the release is holding.
    other = on_own_connection { handler.reserve_stock(reserve_request(order_number: "ORD-OTHER"), nil) }
    sleep SETTLE
    expect(other.alive?).to be(true)

    gate << :commit
    releaser.join
    res = other.value

    expect(res.success).to be(true)
    expect(reserved_quantity).to eq(3)
    expect(StockReservation.where(released_at: nil).pluck(:order_number)).to eq([ "ORD-OTHER" ])
  end

  it "does not make one merchant wait on another merchant's identical order number" do
    # The other half of scoping the ledger's unique index to the merchant. The tombstone race is
    # unaffected — a reserve and the release compensating it carry the same merchant and still
    # collide, which the two examples above prove — but two DIFFERENT merchants naming the same
    # (order_number, sku) were never racing, and while the index was global one of them blocked on
    # the other's uncommitted tuple and then inherited its outcome.
    #
    # The in-flight half is a RELEASE, and that is load-bearing rather than incidental. A release
    # that finds nothing writes its tombstone and then only READS bin_inventories, so it holds the
    # ledger row and no bin row. An in-flight RESERVE would hold every bin row for the sku FOR
    # UPDATE, and the other merchant would block there no matter what the ledger index says — the
    # example would be asserting a non-block that this schema does not provide, and would then hang
    # the file waiting for a thread that is not coming back. Bin contention between two merchants
    # sharing a sku is real and expected; it is bounded by the lock timeout and is not what this
    # index change is about.
    #
    # It is also the exact shape of the denial that made this a defect: merchant B sends one
    # well-formed ReleaseStock for a pair it does not own, and merchant A can no longer reserve it.
    results = Queue.new
    theirs, gate = in_flight(results) do
      handler.release_stock(release_request(principal_id: other_principal), nil)
    end
    expect(results.pop.already_released).to be(true)

    mine = on_own_connection { handler.reserve_stock(reserve_request(key: "K-MINE"), nil) }
    sleep SETTLE
    # Not blocked, and not refused: the other merchant's tombstone is a different key in this index,
    # so it is neither an obstacle to collide with nor a row this lookup can see.
    expect(mine.alive?).to be(false)
    res = mine.value
    expect(res.success).to be(true)

    gate << :commit
    theirs.join

    expect(reserved_quantity).to eq(3)

    rows = StockReservation.where(order_number: "ORD-C").order(:merchant_id)
    expect(rows.count).to eq(2)
    expect(rows.find_by(merchant_id: @merchant.id))
      .to have_attributes(quantity: 3, released_at: nil)
    expect(rows.find_by(merchant_id: @other_merchant.id).quantity).to eq(0)
    expect(rows.find_by(merchant_id: @other_merchant.id).released_at).to be_present
  end

  it "moves the counter exactly once under a burst of identical duplicates" do
    responses = 3.times.map do
      on_own_connection { handler.reserve_stock(reserve_request(key: "K-BURST"), nil) }
    end.map(&:value)

    expect(responses.map(&:success).uniq).to eq([ true ])
    expect(responses.map(&:to_proto).uniq.size).to eq(1)
    expect(StockReservation.count).to eq(1)
    expect(StockOperation.count).to eq(1)
    expect(reserved_quantity).to eq(3)
  end

  it "answers RESERVATION_IN_PROGRESS rather than raising when the wait runs out" do
    # Driven through the real knob rather than a stub. This file runs with transactional fixtures
    # off and calls into the code under test from a second thread, and rspec-mocks is not
    # thread-safe: a stub installed on the main thread and invoked concurrently is a documented
    # flake vector, and a flake in the one file that exists to prove the concurrency claims is
    # exactly where it destroys trust. ENV is process-global and read fresh on every call, so
    # setting it needs no stub at all.
    #
    # 1 second is the clamp floor — comfortably under the 0.5s settle plus the winner's held
    # transaction, and comfortably over the time the loser needs to reach its claim INSERT.
    with_lock_timeout("1") do
      results = Queue.new
      winner, gate = in_flight(results) { handler.reserve_stock(reserve_request(key: "K-1"), nil) }
      results.pop

      res = ActiveRecord::Base.connection_pool.with_connection do
        handler.reserve_stock(reserve_request(key: "K-1"), nil)
      end

      expect(res.success).to be(false)
      expect(res.error.error_code).to eq("RESERVATION_IN_PROGRESS")

      gate << :commit
      winner.join
      # The original still committed exactly once; the timeout changed nothing.
      expect(reserved_quantity).to eq(3)
    end
  end

  # The three waits, each answered about the statement that actually timed out.
  #
  # There are exactly three rows a call inside the gate can block on, and they mean three different
  # things to whoever reads the log. Collapsing any two of them produces the estate's recurring
  # failure mode — a definite-sounding answer whose stated cause is wrong — so each one has its own
  # code and each code is asserted here against a real second connection rather than described in a
  # comment. Verified against Postgres's own statement log with `log_statement=all`: the cancelled
  # statement in the three examples below is, in order, the INSERT into stock_operations, the INSERT
  # into stock_reservations, and the `SELECT ... FROM bin_inventories ... FOR UPDATE`.
  #
  # If a future change folds two of these together, exactly one of these examples goes red.
  describe "the code on a wait that runs out names the row that was actually held" do
    it "says RESERVATION_IN_PROGRESS when the wait is on the claim — a real duplicate" do
      with_lock_timeout("1") do
        results = Queue.new
        winner, gate = in_flight(results) { handler.reserve_stock(reserve_request(key: "K-1"), nil) }
        results.pop

        res = ActiveRecord::Base.connection_pool.with_connection do
          handler.reserve_stock(reserve_request(key: "K-1"), nil)
        end

        expect(res.error.error_code).to eq("RESERVATION_IN_PROGRESS")
        gate << :commit
        winner.join
      end
    end

    it "says STOCK_LEDGER_BUSY when a release waits on the reserve it is compensating" do
      # The dominant contention in this design, not a corner: the saga compensates steps that are
      # still Attempting. Before this code existed it answered "another order is holding this sku's
      # rows", which named a different order for a wait on THIS order's own uncommitted reserve.
      with_lock_timeout("1") do
        results = Queue.new
        reserver, gate = in_flight(results) { handler.reserve_stock(reserve_request, nil) }
        results.pop

        res = ActiveRecord::Base.connection_pool.with_connection do
          handler.release_stock(release_request, nil)
        end

        expect(res.success).to be(false)
        expect(res.error.error_code).to eq("STOCK_LEDGER_BUSY")
        expect(res.error.message).to include("this order and sku")

        gate << :commit
        reserver.join
        # Nothing was changed by the refusal: the reserve still committed exactly once.
        expect(reserved_quantity).to eq(3)
      end
    end

    it "says STOCK_LEDGER_BUSY when a second release waits on the ledger row FOR UPDATE" do
      # A different key, so the claim does not collide — the wait is the `SELECT ... FOR UPDATE` on
      # stock_reservations, and it is still this order's own row.
      handler.reserve_stock(reserve_request, nil)

      with_lock_timeout("1") do
        results = Queue.new
        first, gate = in_flight(results) do
          handler.release_stock(release_request(key: "K-REL-A"), nil)
        end
        results.pop

        res = ActiveRecord::Base.connection_pool.with_connection do
          handler.release_stock(release_request(key: "K-REL-B"), nil)
        end

        expect(res.error.error_code).to eq("STOCK_LEDGER_BUSY")
        gate << :commit
        first.join
      end
    end

    it "says STOCK_LOCK_TIMEOUT only when the wait is on a bin row held by a different order" do
      with_lock_timeout("1") do
        results = Queue.new
        holder, gate = in_flight(results) do
          handler.reserve_stock(reserve_request(order_number: "ORD-HOLDER"), nil)
        end
        results.pop

        res = ActiveRecord::Base.connection_pool.with_connection do
          handler.reserve_stock(reserve_request(order_number: "ORD-OTHER"), nil)
        end

        expect(res.error.error_code).to eq("STOCK_LOCK_TIMEOUT")
        expect(res.error.message).to include("bin rows")

        gate << :commit
        holder.join
      end
    end
  end

  it "refuses a duplicate reserve whose release is still in flight, instead of replaying it" do
    # IdempotentOperation#still_held? reads the ledger row FOR UPDATE, and the lock is the point.
    # Unlocked, this read saw the in-flight release's PRE-image under READ COMMITTED, reported the
    # stock as held, and served the stored `success: true` — measured, on this database, at
    # `bin_location: "C-01"` for a hold that was released a millisecond later. That is the exact
    # answer the REPLAY_REFUSED branch exists to prevent.
    handler.reserve_stock(reserve_request(key: "K-DUP"), nil)
    expect(reserved_quantity).to eq(3)

    results = Queue.new
    releaser, gate = in_flight(results) { handler.release_stock(release_request, nil) }
    expect(results.pop.success).to be(true)

    duplicate = on_own_connection { handler.reserve_stock(reserve_request(key: "K-DUP"), nil) }
    sleep SETTLE
    # Blocked on the ledger row rather than answering over the top of an uncommitted release.
    expect(duplicate.alive?).to be(true)

    gate << :commit
    releaser.join
    res = duplicate.value

    expect(res.success).to be(false)
    expect(res.error.error_code).to eq("STOCK_RESERVATION_RELEASED")
    expect(reserved_quantity).to eq(0)

    record = StockOperation.find_by(operation: "reserve")
    expect(record.replay_refused_count).to eq(1)
    # Counted as a refusal and NOT as a served replay, so runbook query 5 stays honest.
    expect(record.replay_count).to eq(0)
  end

  it "makes the operator reclaim wait for an in-flight release, then credit nothing" do
    # `rake stock:release_hold` is the ONLY thing in the estate that puts an abandoned hold's units
    # back, and it runs ReleaseStockService outside the dedupe gate — no stock_operations claim
    # serialises it against a caller. The ledger row's FOR UPDATE is the whole of its protection.
    # If that were not enough, an operator reclaiming a hold that a caller was releasing at the
    # same moment would credit the bin twice and the same units would be sold twice.
    handler.reserve_stock(reserve_request, nil)
    expect(reserved_quantity).to eq(3)

    results = Queue.new
    caller_release, gate = in_flight(results) { handler.release_stock(release_request, nil) }
    expect(results.pop.success).to be(true)
    # Uncommitted, so from every other connection the units still look held.
    expect(reserved_quantity).to eq(3)

    operator = on_own_connection do
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL lock_timeout = 10000")
        Inventory::ReleaseStockService.new(
          merchant: @merchant, order_number: "ORD-C", sku: "SKU-C"
        ).call
      end
    end

    sleep SETTLE
    # Blocked on the caller's FOR UPDATE. It cannot expire a hold whose release is in flight.
    expect(operator.alive?).to be(true)

    gate << :commit
    caller_release.join
    outcome = operator.value

    expect(outcome.message.already_released).to be(true)
    expect(outcome.applied).to be(false)
    # Three units back, once. A second credit would show as 0 - 3 here.
    expect(reserved_quantity).to eq(0)
    expect(StockReservation.held.count).to eq(0)
  end

  def with_lock_timeout(value)
    previous = ENV["WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS"]
    ENV["WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS")
                  : ENV["WAREHOUSE_STOCK_LOCK_TIMEOUT_SECONDS"] = previous
  end
end
