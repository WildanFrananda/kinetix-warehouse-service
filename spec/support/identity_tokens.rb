# typed: false
# frozen_string_literal: true

require "jwt"
require "openssl"

module IdentityTokens
  SIGNING_KEY = OpenSSL::PKey::RSA.generate(2048)
  JWK = JWT::JWK.new(SIGNING_KEY)

  def self.jwks_document
    { keys: [ JWK.export.merge(alg: "RS256", use: "sig") ] }.to_json
  end

  def access_token(principal_id:, user_id: 1, email: "seller@kinetix.test", role: "seller", **overrides)
    claims = {
      sub: principal_id,
      uid: user_id,
      email: email,
      role: role,
      token_use: "access",
      iss: ENV.fetch("JWT_ISSUER"),
      aud: ENV.fetch("JWT_AUDIENCE"),
      iat: Time.now.to_i,
      exp: Time.now.to_i + 900
    }.merge(overrides)

    JWT.encode(claims, IdentityTokens::SIGNING_KEY, "RS256", kid: IdentityTokens::JWK.kid)
  end

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.shared_context "identity issues tokens" do
  include IdentityTokens

  before do
    allow(Net::HTTP).to receive(:get).and_return(IdentityTokens.jwks_document)
    Kinetix::TokenVerifier.instance_variable_set(:@shared, nil)
  end

  after do
    Kinetix::TokenVerifier.instance_variable_set(:@shared, nil)
  end
end
