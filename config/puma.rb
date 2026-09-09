require_relative "../lib/kinetix/json_log_formatter"

threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

puma_log_formatter = Kinetix::JsonLogFormatter.new(source: "puma")
log_formatter { |message| puma_log_formatter.call("INFO", Time.now, nil, message).chomp }

port ENV.fetch("PORT", 3000)

force_shutdown_after Float(ENV.fetch("KINETIX_DRAIN_SECONDS", 20))

plugin :tmp_restart

plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
