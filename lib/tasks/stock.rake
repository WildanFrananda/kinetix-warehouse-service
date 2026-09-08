namespace :stock do
  desc "List stock_reservations still held after WAREHOUSE_ABANDONED_HOLD_HOURS (default 24)"
  task abandoned_holds: :environment do
    report = Inventory::AbandonedHoldReport.new

    if report.rows.empty?
      puts "No hold older than #{report.older_than_hours}h. Nothing is stranded."
    else
      puts "#{report.rows.size} hold(s) older than #{report.older_than_hours}h, " \
           "#{report.units} unit(s) frozen:"
      puts format("%-8s %-24s %-20s %-9s %-9s %s", "ID", "ORDER", "SKU", "QTY", "MERCHANT", "HELD SINCE")
      report.rows.each do |reservation|
        puts format(
          "%-8s %-24s %-20s %-9s %-9s %s",
          reservation.id, reservation.order_number, reservation.sku,
          reservation.quantity, reservation.merchant_id, reservation.created_at
        )
      end
      puts
      puts "Check the owning saga in order-service BEFORE reclaiming any of these: a hold that is"
      puts "merely slow looks identical to one that is abandoned, and releasing a live one sells"
      puts "the same units twice. When you have confirmed the order is dead:"
      puts "    bin/rails 'stock:release_hold[ID]'"
    end

    report.call
  end

  desc "Reclaim ONE abandoned hold by stock_reservations.id, after confirming its order is dead"
  task :release_hold, [ :reservation_id ] => :environment do |_task, args|
    id = args[:reservation_id]
    abort("Usage: bin/rails 'stock:release_hold[RESERVATION_ID]'") if id.blank?

    reservation = StockReservation.find_by(id: id)
    abort("No stock_reservations row with id=#{id}.") if reservation.nil?
    if reservation.released_at.present?
      abort("Reservation #{id} was already released at #{reservation.released_at}. Nothing to do.")
    end

    outcome = ApplicationRecord.transaction do
      Inventory::IdempotentOperation.apply_lock_timeout!

      Inventory::ReleaseStockService.new(
        merchant: reservation.merchant,
        order_number: reservation.order_number,
        sku: reservation.sku
      ).call
    end

    reservation.reload

    beaten = outcome.message.already_released
    credited = outcome.applied

    Rails.logger.warn(
      "stock.idem operator_release reservation_id=#{reservation.id} " \
      "order_number=#{reservation.order_number} sku=#{reservation.sku} " \
      "merchant_id=#{reservation.merchant_id} quantity=#{reservation.quantity} " \
      "credited=#{credited} already_released_by_a_caller=#{beaten} " \
      "released_at=#{reservation.released_at}"
    )

    if beaten
      puts "Reservation #{reservation.id} (#{reservation.order_number} / #{reservation.sku}) was"
      puts "already released before this command took its row lock — a caller got there first."
      puts "Nothing was reclaimed by hand and nothing was credited twice."
    elsif credited
      puts "Released reservation #{reservation.id} (#{reservation.order_number} / " \
           "#{reservation.sku}, #{reservation.quantity} unit(s))."
    else
      puts "Closed reservation #{reservation.id} (#{reservation.order_number} / " \
           "#{reservation.sku}, #{reservation.quantity} unit(s)) WITHOUT crediting any counter."
      puts "The bin it debited is gone, or could not be identified — see the stock.idem"
      puts "release_bin_missing / release_bin_guessed line just logged. Those units are NOT back"
      puts "on the shelf; the ledger row is simply closed."
    end

    puts "remaining_available for #{reservation.sku} is now #{outcome.message.remaining_available}."
    puts "The ledger row is kept, marked released — a late reserve for this pair stays terminal."
  end
end
