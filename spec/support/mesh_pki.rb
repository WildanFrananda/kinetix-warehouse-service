# typed: false
# frozen_string_literal: true

require "openssl"
require "tmpdir"
require "fileutils"

class MeshPki
  attr_reader :server_dir, :ca_pem

  def initialize(trust_domain: Kinetix::Spiffe::TRUST_DOMAIN)
    @trust_domain = trust_domain
    @ca_key = OpenSSL::PKey::EC.generate("prime256v1")
    @ca = certificate("/CN=kinetix spec mesh CA", @ca_key, issuer: nil, extensions: [
      [ "basicConstraints", "CA:TRUE", true ],
      [ "keyUsage", "keyCertSign, cRLSign", true ]
    ])
    @ca_pem = @ca.to_pem
    @server_dir = Dir.mktmpdir("kinetix-spec-mesh")
    key, cert = leaf("warehouse", "DNS:localhost")
    File.write(File.join(@server_dir, "tls.key"), key.to_pem)
    File.write(File.join(@server_dir, "tls.crt"), cert.to_pem)
    File.write(File.join(@server_dir, "ca.pem"), @ca_pem)
  end

  def channel_credentials(service)
    key, cert = leaf(service, nil)
    GRPC::Core::ChannelCredentials.new(@ca_pem, key.to_pem, cert.to_pem)
  end

  def remove
    FileUtils.remove_entry(@server_dir, true)
  end

  private

  def leaf(service, extra_name)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    names = [ "URI:spiffe://#{@trust_domain}/service/#{service}", extra_name ].compact.join(",")
    cert = certificate("/CN=#{service}", key, issuer: @ca, extensions: [
      [ "basicConstraints", "CA:FALSE", true ],
      [ "keyUsage", "digitalSignature", true ],
      [ "extendedKeyUsage", "serverAuth,clientAuth", false ],
      [ "subjectAltName", names, false ]
    ])
    [ key, cert ]
  end

  def certificate(subject, key, issuer:, extensions:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.rand(64)
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    factory = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
    extensions.each { |name, value, critical| cert.add_extension(factory.create_extension(name, value, critical)) }
    cert.sign(issuer ? @ca_key : key, OpenSSL::Digest.new("SHA256"))
    cert
  end
end
