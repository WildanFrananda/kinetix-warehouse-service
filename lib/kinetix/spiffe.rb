# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "openssl"

module Kinetix
  module Spiffe
    extend T::Sig

    DEFAULT_TRUST_DOMAIN = T.let("kinetix.local", String)

    configured_trust_domains = ENV["KINETIX_TRUST_DOMAIN"].to_s.split(",").map(&:strip).reject(&:empty?)
    TRUST_DOMAINS = T.let(
      configured_trust_domains.empty? ? [ DEFAULT_TRUST_DOMAIN ] : configured_trust_domains,
      T::Array[String]
    )
    TRUST_DOMAIN = T.let(T.must(TRUST_DOMAINS.first), String)

    sig { params(peer_cert_pem: T.nilable(String)).returns(T.nilable(String)) }
    def self.id_of(peer_cert_pem)
      return nil if peer_cert_pem.nil? || peer_cert_pem.empty?

      cert = OpenSSL::X509::Certificate.new(peer_cert_pem)
      san = cert.extensions.find { |e| e.oid == "subjectAltName" }&.value
      return nil if san.nil?

      entry = san.to_s.split(/,\s*/).find do |v|
        TRUST_DOMAINS.any? { |domain| v.start_with?("URI:spiffe://#{domain}/") }
      end
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
      id = id_of(peer_cert_pem)
      TRUST_DOMAINS.each do |domain|
        named = service_in(id, domain)
        return named if named
      end
      nil
    end
  end
end
