# typed: strict
# frozen_string_literal: true

module Kinetix
  module PlatformTimeZone
    extend T::Sig

    VARIABLE = "KINETIX_TIME_ZONE"

    sig { params(env: T::Hash[String, String]).returns(ActiveSupport::TimeZone) }
    def self.from_env(env)
      name = env.fetch(VARIABLE) { raise "#{VARIABLE} is required and has no default." }
      zone = ActiveSupport::TimeZone[name]
      raise "#{VARIABLE}=#{name} names no time zone this service knows." if zone.nil?

      zone
    end
  end
end
