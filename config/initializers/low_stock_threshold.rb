# typed: false

require_relative "../../lib/kinetix/low_stock_threshold"

Rails.application.config.x.low_stock_threshold = Kinetix::LowStockThreshold.from_env(ENV.to_h)
