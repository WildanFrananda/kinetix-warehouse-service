# typed: strict
# frozen_string_literal: true

# Required explicitly: these files are loaded by bin/grpc_healthcheck outside the Rails
# boot, where sorbet-runtime is not already on the stack.
require "sorbet-runtime"
require "openssl"

module Kinetix
  module Spiffe
    extend T::Sig

    TRUST_DOMAIN = T.let("kinetix.local", String)

    sig { params(peer_cert_pem: T.nilable(String)).returns(T.nilable(String)) }
    def self.id_of(peer_cert_pem)
      return nil if peer_cert_pem.nil? || peer_cert_pem.empty?

      cert = OpenSSL::X509::Certificate.new(peer_cert_pem)
      san = cert.extensions.find { |e| e.oid == "subjectAltName" }&.value
      return nil if san.nil?

      entry = san.to_s.split(/,\s*/).find { |v| v.start_with?("URI:spiffe://#{TRUST_DOMAIN}/") }
      entry&.delete_prefix("URI:")
    rescue OpenSSL::X509::CertificateError
      nil
    end

    sig { params(peer_cert_pem: T.nilable(String)).returns(T.nilable(String)) }
    def self.service_of(peer_cert_pem)
      id_of(peer_cert_pem)&.delete_prefix("spiffe://#{TRUST_DOMAIN}/service/")
    end
  end
end
