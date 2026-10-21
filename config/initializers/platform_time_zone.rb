# typed: false

require_relative "../../lib/kinetix/platform_time_zone"

Rails.application.config.x.platform_time_zone = Kinetix::PlatformTimeZone.from_env(ENV.to_h)
