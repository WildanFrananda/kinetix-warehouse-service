# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "openssl"

module Kinetix
  module Spiffe
    extend T::Sig

    DEFAULT_TRUST_DOMAIN = T.let("kinetix.local", String)

    configured_trust_domain = ENV["KINETIX_TRUST_DOMAIN"].to_s.strip
    TRUST_DOMAIN = T.let(
      configured_trust_domain.empty? ? DEFAULT_TRUST_DOMAIN : configured_trust_domain,
      String
    )

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

    sig { params(id: T.nilable(String), domain: String).returns(T.nilable(String)) }
    def self.service_in(id, domain)
      return nil if id.nil?

      prefix = "spiffe://#{domain}/service/"
      return nil unless id.start_with?(prefix)

      name = id.delete_prefix(prefix)
      return nil if name.empty? || name.include?("/")

      name
    end

    sig { params(peer_cert_pem: T.nilable(String)).returns(T.nilable(String)) }
    def self.service_of(peer_cert_pem)
      service_in(id_of(peer_cert_pem), TRUST_DOMAIN)
    end
  end
end
