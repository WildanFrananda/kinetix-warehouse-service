# typed: strict
# frozen_string_literal: true

# Required explicitly: these files are loaded by bin/grpc_healthcheck outside the Rails
# boot, where sorbet-runtime is not already on the stack.
require "sorbet-runtime"
require "openssl"

module Kinetix
  class ServiceIdentity
    extend T::Sig

    DEFAULT_DIR = T.let("/pki", String)

    sig { returns(String) }
    attr_reader :cert_pem, :key_pem, :ca_pem

    sig { params(directory: String).void }
    def initialize(directory: ENV.fetch("KINETIX_PKI_DIR", DEFAULT_DIR))
      @directory = T.let(directory, String)
      @cert_pem = T.let(read("tls.crt", "BEGIN CERTIFICATE"), String)
      @key_pem  = T.let(read("tls.key", "PRIVATE KEY"), String)
      @ca_pem   = T.let(read("ca.pem", "BEGIN CERTIFICATE"), String)
    end

    sig { returns(GRPC::Core::ServerCredentials) }
    def server_credentials
      GRPC::Core::ServerCredentials.new(
        @ca_pem,
        [ { private_key: @key_pem, cert_chain: @cert_pem } ],
        true
      )
    end

    sig { returns(GRPC::Core::ChannelCredentials) }
    def channel_credentials
      GRPC::Core::ChannelCredentials.new(@ca_pem, @key_pem, @cert_pem)
    end

    private

    sig { params(name: String, marker: String).returns(String) }
    def read(name, marker)
      path = File.join(@directory, name)
      raise "cannot read #{path}: the service PKI is mounted there; issue it with " \
            "kinetix-infrastructure/bin/kinetix-pki issue" unless File.readable?(path)

      contents = File.read(path)
      raise "#{path} is not a PEM containing #{marker}" unless contents.include?(marker)

      contents
    end
  end
end
