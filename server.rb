# frozen_string_literal: true

# server.rb
# Run with: ruby server.rb [--https]
require 'rack'
require 'rackup'
require 'rackup/handler/falcon'
require 'openssl'

app = proc do |_env|
  [
    200,
    {
      'Content-Type' => 'text/event-stream',
      'Cache-Control' => 'no-cache'
    },
    Enumerator.new do |yielder|
      loop do
        yielder << "data: ping\n\n"
        sleep 15
      end
    rescue Errno::EPIPE, IOError
      # Justified Exception: The architecture requires dropping disconnected clients without emitting stacktraces.
      nil
    end
  ]
end

use_https = ARGV.include?('--https')

if use_https
  puts '[Server] Binding natively to HTTPS over port 8443'

  # Generate spontaneous self-signed cert for dynamic secure testing
  rsa = OpenSSL::PKey::RSA.new(2048)
  cert = OpenSSL::X509::Certificate.new
  cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
  cert.not_before = Time.now
  cert.not_after = Time.now + (365 * 24 * 60 * 60)
  cert.public_key = rsa.public_key
  cert.serial = 0x0
  cert.version = 2
  cert.sign(rsa, OpenSSL::Digest.new('SHA256'))

  ssl_context = OpenSSL::SSL::SSLContext.new
  ssl_context.cert = cert
  ssl_context.key = rsa

  Rackup::Handler::Falcon.run(app, Host: '0.0.0.0', Port: 8443, SSLEnable: true, ssl_context: ssl_context) do |_server|
    trap('INT') do
      puts "\n[Server] Shutting down immediately..."
      exit
    end
  end
else
  puts '[Server] Binding natively to plaintext HTTP over port 8080'
  Rackup::Handler::Falcon.run(app, Host: '0.0.0.0', Port: 8080) do |_server|
    trap('INT') do
      puts "\n[Server] Shutting down immediately..."
      exit
    end
  end
end
