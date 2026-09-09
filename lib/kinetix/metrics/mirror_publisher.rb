# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "counter"
require_relative "mirror"

module Kinetix
  module Metrics
    class MirrorPublisher
      extend T::Sig

      INTERVAL_SECONDS = 5.0
      STOP_WAIT_SECONDS = 2.0

      sig { params(mirror: Mirror, counter: Counter).void }
      def initialize(mirror:, counter:)
        @mirror = mirror
        @counter = counter
        @mutex = T.let(Mutex.new, Mutex)
        @wakeup = T.let(ConditionVariable.new, ConditionVariable)
        @stopping = T.let(false, T::Boolean)
        @publishing = T.let(nil, T.nilable(T::Boolean))
        @thread = T.let(nil, T.nilable(Thread))
      end

      sig { void }
      def start
        @thread = Thread.new do
          Thread.current.name = "kinetix-metrics-mirror"
          loop do
            publish_once
            @mutex.synchronize { @wakeup.wait(@mutex, INTERVAL_SECONDS) unless @stopping }
            break if stopping?
          end
        end
      end

      sig { void }
      def stop
        @mutex.synchronize do
          @stopping = true
          @wakeup.broadcast
        end
        @thread&.join(STOP_WAIT_SECONDS)
        publish_once
      end

      private

      sig { returns(T::Boolean) }
      def stopping?
        @mutex.synchronize { @stopping }
      end

      sig { void }
      def publish_once
        @mirror.publish(@counter)
        log_state(true, nil)
      rescue StandardError => e
        log_state(false, "#{e.class}: #{e.message}")
      end

      sig { params(publishing: T::Boolean, reason: T.nilable(String)).void }
      def log_state(publishing, reason)
        return if @publishing == publishing

        @publishing = publishing
        if publishing
          Rails.logger.info("publishing gRPC server metrics to #{Mirror::KEY}")
        else
          Rails.logger.warn("cannot publish gRPC server metrics to #{Mirror::KEY}: #{reason}")
        end
      end
    end
  end
end
