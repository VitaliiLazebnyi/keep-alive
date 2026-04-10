require 'async'
require 'falcon/server'
require 'protocol/rack/adapter'
require 'io/endpoint/host_endpoint'
require 'io/endpoint/ssl_endpoint'
require 'openssl'

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

app = proc { |_env| [200, { 'Content-Length' => '2' }, ['OK']] }

Sync do |task|
  endpoint = IO::Endpoint.tcp('127.0.0.1', 8443)
  secure_endpoint = IO::Endpoint::SSLEndpoint.new(endpoint, ssl_context: ssl_context)
  
  adapter = Protocol::Rack::Adapter.new(app)
  server = Falcon::Server.new(adapter, secure_endpoint, protocol: Async::HTTP::Protocol::HTTP1, scheme: 'https')
  
  puts "Running..."
  server_task = server.run
  
  task.async do
    sleep 1
    server_task.stop
  end
  
  server_task.wait
end
