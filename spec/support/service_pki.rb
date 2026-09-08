# typed: false
# frozen_string_literal: true

require "openssl"
require "tmpdir"
require "fileutils"

module ServicePki
  FILES = %w[tls.crt tls.key ca.pem].freeze

  def self.install!
    return ENV["KINETIX_PKI_DIR"] if ENV["KINETIX_PKI_DIR"].present?

    directory = Dir.mktmpdir("kinetix-spec-pki")
    at_exit { FileUtils.remove_entry(directory, true) }

    key = OpenSSL::PKey::RSA.generate(2048)
    File.write(File.join(directory, "tls.key"), key.to_pem)
    File.write(File.join(directory, "tls.crt"), self_signed(key).to_pem)
    File.write(File.join(directory, "ca.pem"), File.read(File.join(directory, "tls.crt")))

    ENV["KINETIX_PKI_DIR"] = directory
  end

  def self.self_signed(key)
    name = OpenSSL::X509::Name.parse("/CN=warehouse.kinetix.test")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = name
    cert.issuer = name
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end
end

ServicePki.install!
