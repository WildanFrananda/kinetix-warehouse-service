# frozen_string_literal: true

require "rails_helper"

RSpec.describe Kinetix::TokenVerifier do
  include IdentityTokens

  let(:now) { [ 1_000.0 ] }
  let(:verifier) { described_class.new(clock: -> { now.first }) }
  let(:stranger) { OpenSSL::PKey::RSA.generate(2048) }

  def forged(kid)
    claims = {
      sub: "00000000-0000-4000-8000-000000000001",
      token_use: "access",
      iss: ENV.fetch("JWT_ISSUER"),
      aud: ENV.fetch("JWT_AUDIENCE"),
      exp: Time.now.to_i + 900
    }
    JWT.encode(claims, stranger, "RS256", kid: kid)
  end

  def wait(seconds)
    now[0] = now.first + seconds
  end

  before do
    allow(Net::HTTP).to receive(:get).and_return(IdentityTokens.jwks_document)
  end

  it "answers a known key without asking identity again" do
    token = access_token(principal_id: "00000000-0000-4000-8000-000000000001")

    verifier.verify_access(token)
    verifier.verify_access(token)

    expect(Net::HTTP).to have_received(:get).once
  end

  it "does not ask identity once per request for keys it has never published" do
    verifier.verify_access(access_token(principal_id: "00000000-0000-4000-8000-000000000001"))

    50.times do |i|
      expect { verifier.verify_access(forged("forged-#{i}")) }.to raise_error(described_class::InvalidToken)
    end

    expect(Net::HTTP).to have_received(:get).once
  end

  it "looks for an unknown key again once the interval has passed, and only once" do
    verifier.verify_access(access_token(principal_id: "00000000-0000-4000-8000-000000000001"))
    wait(described_class::UNKNOWN_KEY_REFRESH_SECONDS + 1)

    expect { verifier.verify_access(forged("next")) }.to raise_error(described_class::InvalidToken)
    expect { verifier.verify_access(forged("after")) }.to raise_error(described_class::InvalidToken)

    expect(Net::HTTP).to have_received(:get).twice
  end

  it "says identity could not be asked, not that the token is bad, when the keys cannot be fetched" do
    allow(Net::HTTP).to receive(:get).and_raise(Errno::ECONNREFUSED)
    token = access_token(principal_id: "00000000-0000-4000-8000-000000000001")

    expect { verifier.verify_access(token) }.to raise_error(described_class::KeysUnavailable)
    expect { verifier.verify_access(token) }.to raise_error(described_class::KeysUnavailable)

    expect(Net::HTTP).to have_received(:get).once
  end

  it "accepts the token once identity answers again after the interval" do
    allow(Net::HTTP).to receive(:get).and_raise(Errno::ECONNREFUSED)
    token = access_token(principal_id: "00000000-0000-4000-8000-000000000001")
    expect { verifier.verify_access(token) }.to raise_error(described_class::KeysUnavailable)

    allow(Net::HTTP).to receive(:get).and_return(IdentityTokens.jwks_document)
    wait(described_class::UNKNOWN_KEY_REFRESH_SECONDS + 1)

    expect(verifier.verify_access(token)["token_use"]).to eq("access")
  end
end
