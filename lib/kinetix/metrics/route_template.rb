# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Kinetix
  module Metrics
    module RouteTemplate
      extend T::Sig

      UNMATCHED = "(unmatched)"

      sig { params(request: ActionDispatch::Request).returns(String) }
      def self.for_request(request)
        pattern = request.route_uri_pattern
        return UNMATCHED if pattern.nil?

        normalise(pattern)
      end

      sig { params(pattern: String).returns(String) }
      def self.normalise(pattern)
        template = pattern.sub(/\(\.:format\)\z/, "")
        template = template.gsub(/[:*]([A-Za-z_][A-Za-z0-9_]*)/) { "{#{Regexp.last_match(1)}}" }
        template = template.delete("()")
        template.empty? ? "/" : template
      end
    end
  end
end
