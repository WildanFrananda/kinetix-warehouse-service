# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "json"
require_relative "counter"
require_relative "sample"

module Kinetix
  module Metrics
    class Mirror
      extend T::Sig

      KEY = "kinetix:metrics:kinetix-warehouse-service:grpc_server_calls"

      MAX_AGE_SECONDS = 30.0

      sig { params(redis: T.untyped, key: String, max_age_seconds: Float).void }
      def initialize(redis: REDIS, key: KEY, max_age_seconds: MAX_AGE_SECONDS)
        @redis = redis
        @key = key
        @max_age_seconds = max_age_seconds
      end

      sig { params(counter: Counter).returns(T::Boolean) }
      def publish(counter)
        payload = {
          "published_at" => Time.now.to_f,
          "label_names" => counter.label_names,
          "series" => counter.samples.map { |sample| { "labels" => sample.labels, "value" => sample.value } }
        }

        @redis.set(@key, JSON.generate(payload))
        true
      end

      sig { params(label_names: T::Array[String]).returns(T.nilable(T::Array[Sample])) }
      def read(label_names)
        raw = @redis.get(@key)
        return nil if raw.nil?

        payload = JSON.parse(raw)
        return nil unless payload.is_a?(Hash)
        return nil unless payload["label_names"] == label_names
        return nil if stale?(payload["published_at"])

        series = payload["series"]
        return nil unless series.is_a?(Array)

        series.filter_map { |entry| sample_from(entry, label_names) }
      rescue JSON::ParserError
        nil
      end

      private

      sig { params(published_at: T.untyped).returns(T::Boolean) }
      def stale?(published_at)
        return true unless published_at.is_a?(Numeric)

        (Time.now.to_f - published_at.to_f) > @max_age_seconds
      end

      sig { params(entry: T.untyped, label_names: T::Array[String]).returns(T.nilable(Sample)) }
      def sample_from(entry, label_names)
        return nil unless entry.is_a?(Hash)

        labels = entry["labels"]
        value = entry["value"]
        return nil unless labels.is_a?(Hash) && value.is_a?(Numeric)
        return nil unless labels.keys.sort == label_names.sort

        Sample.new(
          name: "",
          labels: labels.transform_keys(&:to_s).transform_values(&:to_s),
          value: value.to_f
        )
      end
    end
  end
end
