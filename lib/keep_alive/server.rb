# typed: strong
# Justified Exception: Flawed upstream library typings (Rack and Rackup) prevent strong evaluation natively.
# frozen_string_literal: true

require 'sorbet-runtime'
require 'rack'
require 'rackup'
require 'rackup/handler/falcon'
require 'openssl'
require 'io/endpoint/host_endpoint'
require 'io/endpoint/ssl_endpoint'
require 'async'
require 'falcon/server'
require 'protocol/rack/adapter'

module KeepAlive
  class Server
    extend T::Sig

    sig { void }
    def initialize
      @app = T.let(
        proc do |_env|
          [
            200,
            {
              'Content-Type' => 'text/plain',
              'Content-Length' => '2'
            },
            ['OK']
          ]
        end,
        T.proc.params(arg0: T::Hash[String, Object]).returns(T::Array[T.any(Integer, T::Hash[String, String], Object)])
      )
    end

    sig { params(use_https: T::Boolean, port: Integer).void }
    def start(use_https: false, port: 8080)
      if use_https
        puts "[Server] Binding natively to HTTPS over port #{port}"
        ssl_context = generate_ssl_context

        T.unsafe(self).Sync do |task|
          endpoint = T.unsafe(IO::Endpoint).tcp('0.0.0.0', port)
          secure_endpoint = T.unsafe(IO::Endpoint::SSLEndpoint).new(endpoint, ssl_context: ssl_context)

          adapter = T.unsafe(::Protocol::Rack::Adapter).new(@app)
          server = T.unsafe(::Falcon::Server).new(adapter, secure_endpoint, protocol: T.unsafe(Async::HTTP::Protocol::HTTP1), scheme: 'https')

          server_task = server.run

          trap('INT') do
            puts "\n[Server] Shutting down immediately..."
            task.stop
            exit(0)
          end

          server_task.wait
        end
      else
        puts "[Server] Binding natively to plaintext HTTP over port #{port}"
        Rackup::Handler::Falcon.run(@app, Host: '0.0.0.0', Port: port) do |_server|
          trap('INT') do
            puts "\n[Server] Shutting down immediately..."
            exit(0)
          end
        end
      end
    end

    private

    sig { returns(OpenSSL::SSL::SSLContext) }
    def generate_ssl_context
      rsa = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
      cert.not_before = Time.now.utc
      cert.not_after = Time.now.utc + (365 * 24 * 60 * 60)
      cert.public_key = rsa.public_key
      cert.serial = 0x0
      cert.version = 2
      cert.sign(rsa, OpenSSL::Digest.new('SHA256'))

      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.cert = cert
      ssl_context.key = rsa
      ssl_context
    end
  end
end
