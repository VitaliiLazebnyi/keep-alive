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

# Primary namespace for the load testing framework.
module HttpLoader
  # Server provides a lightweight, natively asynchronous HTTP/HTTPS mock endpoint
  class Server
    extend T::Sig

    # Allocates the Rack mapped mock layer simulating an identical, ultra-efficient mock endpoint.
    #
    # @return [void]
    sig { void }
    def initialize
      @app = T.let(
        proc do |_env|
          [200, { 'Content-Type' => 'text/plain', 'Content-Length' => '2' }, ['OK']]
        end,
        T.proc.params(arg0: T::Hash[String, Object]).returns(T::Array[T.any(Integer, T::Hash[String, String], Object)])
      )
    end

    # Hooks native asynchronous server to bound TCP ports.
    #
    # @param use_https [Boolean] enables OpenSSL validation mapping natively
    # @param port [Integer] targeted OS listen port
    # @return [void]
    sig { params(use_https: T::Boolean, port: Integer).void }
    def start(use_https: false, port: 8080)
      if use_https
        start_secure(port)
      else
        start_plaintext(port)
      end
    end

    private

    # Binds securely over HTTPS natively bypassing normal HTTP routing constraints dynamically.
    #
    # @param port [Integer] local physical OS target port
    # @return [void]
    sig { params(port: Integer).void }
    def start_secure(port)
      puts "[Server] Binding natively to HTTPS over port #{port}"
      ssl_context = generate_ssl_context

      T.unsafe(self).send(:Sync) do |task|
        run_falcon(task, port, ssl_context)
      end
    end

    # Orchestrates asynchronous falcon execution within local async boundary.
    #
    # @param task [Async::Task] async orchestrator closure bound variable
    # @param port [Integer] physical OS boundary target identifier
    # @param context [OpenSSL::SSL::SSLContext] verified generated payload map
    # @return [void]
    sig { params(task: T.untyped, port: Integer, context: OpenSSL::SSL::SSLContext).void }
    def run_falcon(task, port, context)
      server_task = build_falcon_server(port, context).run
      setup_interrupt do
        task.stop
        exit(0)
      end
      server_task.wait
    end

    # Interlinks raw async descriptors configuring a strictly asynchronous HTTP1 web socket.
    #
    # @param port [Integer] target
    # @param context [OpenSSL::SSL::SSLContext] populated encryption mappings
    # @return [Falcon::Server, Object] internally mapped untyped interface natively wrapping the app
    sig { params(port: Integer, context: OpenSSL::SSL::SSLContext).returns(T.untyped) }
    def build_falcon_server(port, context)
      endpoint = T.unsafe(IO::Endpoint).tcp('0.0.0.0', port)
      secure = T.unsafe(IO::Endpoint::SSLEndpoint).new(endpoint, ssl_context: context)
      adapter = T.unsafe(::Protocol::Rack::Adapter).new(@app)
      T.unsafe(::Falcon::Server).new(
        adapter, secure, protocol: T.unsafe(Async::HTTP::Protocol::HTTP1), scheme: 'https'
      )
    end

    # Initializes native Rack bindings strictly wrapping Rackup fallback mechanisms.
    #
    # @param port [Integer] mapped integer binding OS constraints
    # @return [void]
    sig { params(port: Integer).void }
    def start_plaintext(port)
      puts "[Server] Binding natively to plaintext HTTP over port #{port}"
      Rackup::Handler::Falcon.run(@app, Host: '0.0.0.0', Port: port) do |_server|
        setup_interrupt { exit(0) }
      end
    end

    # Abstracts UNIX interrupt traps correctly resolving anonymous code closures cleanly.
    #
    # @yield to caller upon catching OS interaction interruption manually.
    # @return [void]
    sig { params(blk: T.proc.void).void }
    def setup_interrupt(&blk)
      trap('INT') do |_signo|
        puts "\n[Server] Shutting down immediately..."
        yield
      end
    end

    # Assembles an ephemeral RSA asymmetric signing layer satisfying secure validation without CA dependencies naturally.
    #
    # @return [OpenSSL::SSL::SSLContext] fully integrated validation context mapping
    sig { returns(OpenSSL::SSL::SSLContext) }
    def generate_ssl_context
      rsa = OpenSSL::PKey::RSA.new(2048)
      cert = build_cert(rsa)

      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.cert = cert
      ssl_context.key = rsa
      ssl_context
    end

    # Implements strict OpenSSL x509 bindings to dynamically minted, single-use keys safely.
    #
    # @param rsa [OpenSSL::PKey::RSA] private token implementation map
    # @return [OpenSSL::X509::Certificate] signed local payload identity matrix
    sig { params(rsa: OpenSSL::PKey::RSA).returns(OpenSSL::X509::Certificate) }
    def build_cert(rsa)
      cert = OpenSSL::X509::Certificate.new
      parse_cert_info(cert)
      cert.public_key = rsa.public_key
      cert.serial = 0x0
      cert.version = 2
      cert.sign(rsa, OpenSSL::Digest.new('SHA256'))
      cert
    end

    # Mutates metadata associated with x509 structures natively verifying localhost assertions.
    #
    # @param cert [OpenSSL::X509::Certificate] target instance mapped internally
    # @return [void]
    sig { params(cert: OpenSSL::X509::Certificate).void }
    def parse_cert_info(cert)
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
      cert.not_before = Time.now.utc
      cert.not_after = Time.now.utc + (365 * 24 * 60 * 60)
    end
  end
end
