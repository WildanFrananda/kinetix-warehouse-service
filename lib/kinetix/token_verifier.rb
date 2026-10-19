# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "jwt"
require "net/http"
require "json"

module Kinetix
  class TokenVerifier
    extend T::Sig

    class InvalidToken < StandardError; end

    class KeysUnavailable < StandardError; end

    UNKNOWN_KEY_REFRESH_SECONDS = T.let(10.0, Float)

    sig { params(clock: T.nilable(T.proc.returns(Float))).void }
    def initialize(clock: nil)
      @jwks_url     = T.let(require_env("IDENTITY_JWKS_URL"), String)
      @issuer       = T.let(require_env("JWT_ISSUER"), String)
      @audience     = T.let(require_env("JWT_AUDIENCE"), String)
      @keys         = T.let({}, T::Hash[String, OpenSSL::PKey::RSA])
      @mutex        = T.let(Mutex.new, Mutex)
      @refreshing   = T.let(Mutex.new, Mutex)
      @clock        = T.let(clock, T.nilable(T.proc.returns(Float)))
      @last_refresh = T.let(nil, T.nilable(Float))
      @last_failed  = T.let(false, T::Boolean)
    end

    sig { returns(Kinetix::TokenVerifier) }
    def self.shared
      @shared = T.let(@shared, T.nilable(Kinetix::TokenVerifier))
      @shared ||= new
    end

    sig { params(token: String).returns(T::Hash[String, T.untyped]) }
    def verify_access(token)
      header = JWT.decode(token, nil, false).last
      raise InvalidToken unless header.is_a?(Hash)

      raise InvalidToken unless header["alg"] == "RS256"

      kid = header["kid"].to_s
      raise InvalidToken if kid.empty?

      key = lookup(kid) || refresh_for_unknown_key(kid)
      if key.nil?
        unreachable = @mutex.synchronize { @last_failed }
        raise KeysUnavailable, "identity's signing keys could not be fetched" if unreachable

        raise InvalidToken
      end

      claims, = JWT.decode(
        token, key, true,
        algorithm: "RS256",
        iss: @issuer, verify_iss: true,
        aud: @audience, verify_aud: true,
        verify_expiration: true,
        required_claims: %w[exp iss aud sub]
      )
      raise InvalidToken unless claims.is_a?(Hash)

      raise InvalidToken unless claims["token_use"] == "access"

      claims
    rescue JWT::DecodeError, JWT::VerificationError, OpenSSL::PKey::PKeyError
      raise InvalidToken
    end

    sig { returns(Integer) }
    def refresh!
      @mutex.synchronize { @last_refresh = now }
      count = fetch_keys
      @mutex.synchronize { @last_failed = false }
      count
    rescue StandardError => e
      @mutex.synchronize { @last_failed = true }
      raise KeysUnavailable, "#{@jwks_url}: #{e.message}"
    end

    private

    sig { params(kid: String).returns(T.nilable(OpenSSL::PKey::RSA)) }
    def refresh_for_unknown_key(kid)
      @refreshing.synchronize do
        known = lookup(kid)
        return known unless known.nil?

        last = @mutex.synchronize { @last_refresh }
        return nil if !last.nil? && now - last < UNKNOWN_KEY_REFRESH_SECONDS

        begin
          refresh!
        rescue KeysUnavailable
          nil
        end

        lookup(kid)
      end
    end

    sig { returns(Float) }
    def now
      clock = @clock
      return clock.call unless clock.nil?

      Process.clock_gettime(Process::CLOCK_MONOTONIC).to_f
    end

    sig { returns(Integer) }
    def fetch_keys
      body = Net::HTTP.get(URI(@jwks_url))
      raise "#{@jwks_url} returned no body" if body.nil?

      document = JSON.parse(body)
      fresh = T.let({}, T::Hash[String, OpenSSL::PKey::RSA])

      Array(document["keys"]).each do |jwk|
        next unless jwk["alg"].nil? || jwk["alg"] == "RS256"

        kid = jwk["kid"].to_s
        next if kid.empty?

        fresh[kid] = JWT::JWK.import(jwk).verify_key
      end

      raise "#{@jwks_url} published no usable RS256 keys" if fresh.empty?

      @mutex.synchronize { @keys = fresh }
      fresh.size
    end

    sig { params(kid: String).returns(T.nilable(OpenSSL::PKey::RSA)) }
    def lookup(kid)
      @mutex.synchronize { @keys[kid] }
    end

    sig { params(name: String).returns(String) }
    def require_env(name)
      ENV.fetch(name) { raise "#{name} is required and has no default." }
    end
  end
end
