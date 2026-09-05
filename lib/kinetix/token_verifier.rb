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

    sig { void }
    def initialize
      @jwks_url = T.let(require_env("IDENTITY_JWKS_URL"), String)
      @issuer   = T.let(require_env("JWT_ISSUER"), String)
      @audience = T.let(require_env("JWT_AUDIENCE"), String)
      @keys     = T.let({}, T::Hash[String, OpenSSL::PKey::RSA])
      @mutex    = T.let(Mutex.new, Mutex)
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

      key = lookup(kid)
      if key.nil?
        refresh!
        key = lookup(kid)
      end
      raise InvalidToken if key.nil?

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

    private

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
