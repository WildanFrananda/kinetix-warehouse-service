# typed: strict
# frozen_string_literal: true

require "redis"

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
REDIS = T.let(Redis.new(url: redis_url), T.untyped)
