# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "json"
require "logger"
require "time"
require_relative "request_id"

module Kinetix
  class JsonLogFormatter < ::Logger::Formatter
    extend T::Sig

    sig { params(source: String).void }
    def initialize(source: File.basename($PROGRAM_NAME))
      @source = source
      super()
    end

    sig do
      params(
        severity: T.untyped,
        timestamp: T.untyped,
        progname: T.untyped,
        message: T.untyped
      ).returns(String)
    end
    def call(severity, timestamp, progname, message)
      entry = {
        "timestamp" => at(timestamp),
        "level" => severity.to_s,
        "logger" => logger_name(progname),
        "message" => text(message),
        "request_id" => Kinetix::RequestId.current
      }

      "#{JSON.generate(entry)}\n"
    end

    private

    sig { params(timestamp: T.untyped).returns(String) }
    def at(timestamp)
      timestamp.respond_to?(:getutc) ? timestamp.getutc.iso8601(3) : Time.now.utc.iso8601(3)
    end

    sig { params(progname: T.untyped).returns(String) }
    def logger_name(progname)
      name = progname.to_s
      name.empty? ? @source : name
    end

    sig { params(message: T.untyped).returns(String) }
    def text(message)
      raw = case message
      when String then message
      when Exception then "#{message.class}: #{message.message}"
      else message.inspect
      end

      raw.valid_encoding? ? raw : raw.scrub("?")
    end
  end
end
