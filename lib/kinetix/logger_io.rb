# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Kinetix
  class LoggerIo
    extend T::Sig

    sig { params(logger: T.untyped, severity: Symbol).void }
    def initialize(logger:, severity: :info)
      @logger = logger
      @severity = severity
      @buffer = T.let(+"", String)
      @mutex = T.let(Mutex.new, Mutex)
    end

    sig { params(string: T.untyped).returns(Integer) }
    def write(string)
      text = string.to_s
      @mutex.synchronize do
        @buffer << text
        while (index = @buffer.index("\n"))
          line = T.must(@buffer.slice!(0, index + 1)).chomp
          @logger.public_send(@severity, line) unless line.empty?
        end
      end
      text.bytesize
    end

    sig { params(string: T.untyped).returns(NilClass) }
    def <<(string)
      write(string)
      nil
    end

    sig { void }
    def flush; end

    sig { returns(T::Boolean) }
    def sync
      true
    end

    sig { params(value: T::Boolean).returns(T::Boolean) }
    def sync=(value)
      value
    end
  end
end
