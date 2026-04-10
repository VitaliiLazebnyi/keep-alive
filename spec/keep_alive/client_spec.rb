# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'async'
require 'async/semaphore'
require 'keep_alive/client'

RSpec.describe KeepAlive::Client do
  before do
    allow($stdout).to receive(:puts)
    allow(File).to receive(:write)
    allow(File).to receive(:open)
  end

  describe '#initialize' do
    it 'maps config params correctly' do
      client = described_class.new(
        connections: 10, target_urls: ['http://test.com', 'http://test2.com'], use_https: false,
        verbose: true, ping: false, ping_period: 2, keep_alive_timeout: 4.0,
        connections_per_second: 5, max_concurrent_connections: 5,
        reopen_closed_connections: true, reopen_interval: 2.0,
        read_timeout: 10.0, user_agent: 'SpecAgent',
        jitter: 0.1, track_status_codes: true,
        ramp_up: 120.0, bind_ips: ['127.0.0.1', '127.0.0.2'],
        proxy_pool: ['http://proxy1:80', 'http://proxy2:80'],
        qps_per_connection: 10,
        headers: { 'Authorization' => 'Bearer token' },
        slowloris_delay: 5.0
      )

      expect(client.instance_variable_get(:@max_concurrent_connections)).to eq(5)
      expect(client.instance_variable_get(:@ping)).to eq(false)
      expect(client.instance_variable_get(:@user_agent)).to eq('SpecAgent')
      expect(client.instance_variable_get(:@ramp_up)).to eq(120.0)
      expect(client.instance_variable_get(:@bind_ips)).to eq(['127.0.0.1', '127.0.0.2'])
      expect(client.instance_variable_get(:@proxy_pool)).to eq(['http://proxy1:80', 'http://proxy2:80'])
      expect(client.instance_variable_get(:@qps_per_connection)).to eq(10)
      expect(client.instance_variable_get(:@headers)).to eq({ 'Authorization' => 'Bearer token' })
      expect(client.instance_variable_get(:@slowloris_delay)).to eq(5.0)
    end
  end

  describe '#start' do
    let(:client) { described_class.new(connections: 2, connections_per_second: 10, max_concurrent_connections: 1, verbose: true) }

    it 'executes Async logic with semaphore and ratelimiting', rspec: true do
      expect(client).to receive(:execute_connection).with(0)
      expect(client).to receive(:execute_connection).with(1)
      allow(client).to receive(:trap).with('INT')

      expect_any_instance_of(Async::Task).to receive(:sleep).with(0.1).twice
      client.start
    end

    context 'with ramp_up' do
      let(:client) { described_class.new(connections: 4, ramp_up: 10.0, max_concurrent_connections: 4, verbose: true) }

      it 'calculates delay properly overriding connections_per_second', rspec: true do
        expect(client).to receive(:execute_connection).exactly(4).times
        allow(client).to receive(:trap).with('INT')

        # loop calculates: 10.0 / 4 = 2.5 delay
        expect_any_instance_of(Async::Task).to receive(:sleep).with(2.5).exactly(4).times
        client.start
      end
    end
  end

  describe 'internal execution helpers' do
    let(:client) { described_class.new(connections: 1, read_timeout: 5.0, user_agent: 'TestAgent') }

    context 'when targeting http locally' do
      it 'initializes generic http target correctly', rspec: true do
        expect(client.instance_variable_get(:@protocol_label)).to eq('HTTP')
        expect(client.instance_variable_get(:@target_contexts).first[:uri].to_s).to eq('http://localhost:8080')
        expect(client.instance_variable_get(:@target_contexts).first[:http_args]).to include(read_timeout: 5.0)
        expect(client.instance_variable_get(:@target_contexts).first[:http_args]).to have_key(:ipaddr)
      end

      it 'executes the connection safely and closes if not reopening', rspec: true do
        expect(client).to receive(:run_http_session).with(0, anything)
        expect(client).not_to receive(:sleep)
        client.send(:execute_connection, 0)
      end
    end

    context 'reopening connections' do
      let(:client) { described_class.new(connections: 1, reopen_closed_connections: true, reopen_interval: 0.1) }
      it 'reopens and sleeps interval', rspec: true do
        has_run = false
        allow(client).to receive(:run_http_session)
        allow(client).to receive(:sleep)

        allow(client).to receive(:loop) do |&block|
          unless has_run
            has_run = true
            block.call
          end
        end
        client.send(:execute_connection, 0)
        expect(client).to have_received(:sleep).with(0.1)
      end
    end

    context 'calculate_sleep with jitter' do
      let(:client) { described_class.new(connections: 1, jitter: 0.5) }

      it 'randomizes sleep mathematically within variance', rspec: true do
        allow(client).to receive(:rand).with(-2.5..2.5).and_return(1.0)
        expect(client.send(:calculate_sleep, 5.0)).to eq(6.0)
      end
    end
  end

  describe 'run_http_session' do
    context 'with keep_alive_timeout and no ping' do
      let(:client) { described_class.new(connections: 1, keep_alive_timeout: 0.1, ping: false) }

      it 'respects keep alive timeout without pinging' do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(mock_response).to receive(:read_body)

        allow(client).to receive(:sleep)

        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time + 0.2)

        client.send(:run_http_session, 0, time)
      end
    end

    context 'with multiple bind_ips' do
      let(:client) { described_class.new(connections: 2, bind_ips: ['192.168.1.1', '192.168.1.2'], keep_alive_timeout: 0.1) }

      it 'alternates local_host sequentially via index' do
        mock_http = instance_double(Net::HTTP)
        allow(mock_http).to receive(:request)

        # Connection 0 -> uses index 0 ('192.168.1.1')
        expect(Net::HTTP).to receive(:start).with('localhost', 8080, hash_including(local_host: '192.168.1.1')).and_yield(mock_http)
        client.send(:run_http_session, 0, Time.now)

        # Connection 1 -> uses index 1 ('192.168.1.2')
        expect(Net::HTTP).to receive(:start).with('localhost', 8080, hash_including(local_host: '192.168.1.2')).and_yield(mock_http)
        client.send(:run_http_session, 1, Time.now)
      end
    end

    context 'with proxy_pool' do
      let(:client) { described_class.new(connections: 2, proxy_pool: ['http://proxy1:80', 'http://user:pass@proxy2:81'], keep_alive_timeout: 0.1) }

      it 'alternates proxy details sequentially' do
        mock_http = instance_double(Net::HTTP)
        allow(mock_http).to receive(:request)

        # Connection 0 -> proxy1
        expect(Net::HTTP).to receive(:start).with('localhost', 8080, hash_including(proxy_address: 'proxy1', proxy_port: 80)).and_yield(mock_http)
        client.send(:run_http_session, 0, Time.now)

        # Connection 1 -> proxy2 with auth
        proxy2_args = hash_including(
          proxy_address: 'proxy2', proxy_port: 81,
          proxy_user: 'user', proxy_pass: 'pass'
        )
        expect(Net::HTTP).to receive(:start).with('localhost', 8080, proxy2_args).and_yield(mock_http)
        client.send(:run_http_session, 1, Time.now)
      end
    end

    context 'with custom headers' do
      let(:client) do
        described_class.new(connections: 1, ping: false, headers: { 'Authorization' => 'Bearer XXX', 'X-Custom' => 'Value' }, keep_alive_timeout: 0.1)
      end

      it 'injects headers into base request' do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)

        expect(mock_http).to receive(:request).at_least(:once) do |req|
          expect(req['Authorization']).to eq('Bearer XXX')
          expect(req['X-Custom']).to eq('Value')
        end
        allow(client).to receive(:sleep)
        client.send(:run_http_session, 0, Time.now)
      end
    end

    context 'with qps_per_connection active' do
      let(:client) { described_class.new(connections: 1, ping: false, keep_alive_timeout: 0.0, qps_per_connection: 10) }

      it 'replaces passive pinging with active GET requests' do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)

        # Original GET keep-alive initialization
        allow(mock_http).to receive(:request) do |_req, &block|
          block&.call(mock_response)
          mock_response
        end
        allow(mock_response).to receive(:read_body)
        allow(mock_response).to receive(:is_a?).and_return(false)

        allow(client).to receive(:sleep)

        expect(client).to receive(:sleep).with(0.1) # 1.0 / 10 = 0.1
        client.send(:run_http_session, 0, Time.now)
      end
    end

    context 'with slowloris_delay' do
      let(:client) { described_class.new(connections: 1, ping: false, slowloris_delay: 1.0, keep_alive_timeout: 0.0) }

      it 'bypasses normal Net::HTTP formatting and manually forces byte-by-byte socket writes' do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)

        mock_socket_wrapper = double('socket_wrapper')
        mock_io = double('io')

        allow(mock_http).to receive(:instance_variable_get).with(:@socket).and_return(mock_socket_wrapper)
        allow(mock_socket_wrapper).to receive(:io).and_return(mock_io)

        allow(mock_io).to receive(:write)
        allow(mock_io).to receive(:flush)
        allow(client).to receive(:sleep)

        allow(client).to receive(:loop) do |&block|
          block.call
          break
        end

        expect(mock_io).to receive(:write).at_least(:once)
        expect(mock_io).to receive(:flush).at_least(:once)

        # We expect test to run through the payload each_char then hit the eternal loop once!
        client.send(:run_http_session, 0, Time.now)
      end
    end

    context 'with pinging' do
      let(:client) { described_class.new(connections: 1, ping: true, ping_period: 1, keep_alive_timeout: 0.0) }

      it 'pings' do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |req, &block|
          block&.call(mock_response) if req.is_a?(Net::HTTP::Get)
          mock_response
        end
        allow(mock_response).to receive(:read_body)
        allow(mock_response).to receive(:is_a?).and_return(false)

        allow(client).to receive(:sleep)
        client.send(:run_http_session, 0, Time.now)
        expect(client).to have_received(:sleep).with(1)
      end
    end

    context 'with pinging and status codes' do
      let(:client) { described_class.new(connections: 1, ping: true, ping_period: 1, keep_alive_timeout: 0.0, track_status_codes: true) }

      it 'logs status on non-success' do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPTooManyRequests)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |req, &block|
          block&.call(mock_response) if req.is_a?(Net::HTTP::Get)
          mock_response
        end
        allow(mock_response).to receive(:read_body)
        allow(mock_response).to receive(:is_a?).and_return(false)
        allow(mock_response).to receive(:code).and_return('429')

        allow(client).to receive(:sleep)
        expect(client).to receive(:log_info).with(/Upstream returned HTTP 429/)
        expect(client).to receive(:log_info).with(/Connection established/)
        expect(client).to receive(:log_info).with(/Connection gracefully closed/)
        client.send(:run_http_session, 0, Time.now)
      end
    end
  end

  describe 'error rescuing' do
    let(:client) { described_class.new(connections: 1) }

    it 'rescues EMFILE', rspec: true do
      allow(File).to receive(:open).and_call_original
      allow(Net::HTTP).to receive(:start).and_raise(Errno::EMFILE, 'Too many open files')
      expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      client.instance_variable_get(:@log_queue) << :terminate
      client.instance_variable_get(:@logger_thread).join
    end

    it 'rescues EADDRNOTAVAIL', rspec: true do
      allow(File).to receive(:open).and_call_original
      allow(Net::HTTP).to receive(:start).and_raise(Errno::EADDRNOTAVAIL)
      expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      client.instance_variable_get(:@log_queue) << :terminate
      client.instance_variable_get(:@logger_thread).join
    end

    it 'rescues generic standard errors', rspec: true do
      allow(File).to receive(:open).and_call_original
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, 'Misc failure')
      expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      client.instance_variable_get(:@log_queue) << :terminate
      client.instance_variable_get(:@logger_thread).join
    end
  end

  describe 'logging' do
    let(:verbose_client) { described_class.new(connections: 1, verbose: true) }
    let(:quiet_client) { described_class.new(connections: 1, verbose: false) }

    it 'logs info when verbose' do
      allow(File).to receive(:open).and_call_original
      verbose_client.send(:log_info, 'test')
      verbose_client.instance_variable_get(:@log_queue) << :terminate
      verbose_client.instance_variable_get(:@logger_thread).join
    end

    it 'skips logging info when not verbose' do
      allow(File).to receive(:open).and_call_original
      quiet_client.send(:log_info, 'test')
      quiet_client.instance_variable_get(:@log_queue) << :terminate
      quiet_client.instance_variable_get(:@logger_thread).join
    end
  end
end
