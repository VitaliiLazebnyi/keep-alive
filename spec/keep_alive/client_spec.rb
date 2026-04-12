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
    it 'raises ArgumentError on connections 0' do
      expect { described_class.new(connections: 0) }.to raise_error(ArgumentError, /connections must be >= 1/)
    end

    it 'raises ArgumentError on invalid ping_period' do
      expect { described_class.new(connections: 1, ping_period: -1) }.to raise_error(ArgumentError, /ping_period must be >= 0/)
    end

    it 'raises ArgumentError on invalid timeout' do
      expect { described_class.new(connections: 1, keep_alive_timeout: -1.0) }.to raise_error(ArgumentError, /keep_alive_timeout must be >= 0.0/)
    end

    it 'raises ArgumentError on invalid max_concurrent' do
      expect do
        described_class.new(connections: 1, max_concurrent_connections: 0)
      end.to raise_error(ArgumentError, /max_concurrent_connections must be >= 1/)
    end

    context 'when providing illegal arguments naturally dropping out' do
      it 'raises ArgumentError consistently logging mathematically missing limits' do
        expect { described_class.new(connections: 1, connections_per_second: -1) }.to raise_error(ArgumentError, /connections_per_second/)
        expect { described_class.new(connections: 1, reopen_interval: -1.0) }.to raise_error(ArgumentError, /reopen_interval/)
        expect { described_class.new(connections: 1, read_timeout: -1.0) }.to raise_error(ArgumentError, /read_timeout/)
        expect { described_class.new(connections: 1, jitter: -1.0) }.to raise_error(ArgumentError, /jitter/)
        expect { described_class.new(connections: 1, ramp_up: -1.0) }.to raise_error(ArgumentError, /ramp_up/)
        expect { described_class.new(connections: 1, qps_per_connection: -1) }.to raise_error(ArgumentError, /qps_per_connection/)
        expect { described_class.new(connections: 1, slowloris_delay: -1.0) }.to raise_error(ArgumentError, /slowloris/)
      end
    end

    context 'with valid parameters' do
      let(:client) do
        described_class.new(
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
      end

      it('maps max_concurrent_connections') { expect(client.instance_variable_get(:@max_concurrent_connections)).to eq(5) }
      it('maps ping') { expect(client.instance_variable_get(:@ping)).to be(false) }
      it('maps user_agent') { expect(client.instance_variable_get(:@user_agent)).to eq('SpecAgent') }
      it('maps ramp_up') { expect(client.instance_variable_get(:@ramp_up)).to eq(120.0) }
      it('maps bind_ips') { expect(client.instance_variable_get(:@bind_ips)).to eq(['127.0.0.1', '127.0.0.2']) }
      it('maps proxy_pool') { expect(client.instance_variable_get(:@proxy_pool)).to eq(['http://proxy1:80', 'http://proxy2:80']) }
      it('maps qps_per_connection') { expect(client.instance_variable_get(:@qps_per_connection)).to eq(10) }
      it('maps headers') { expect(client.instance_variable_get(:@headers)).to eq({ 'Authorization' => 'Bearer token' }) }
      it('maps slowloris_delay') { expect(client.instance_variable_get(:@slowloris_delay)).to eq(5.0) }
    end
  end

  describe '#start' do
    let(:client_rate) { described_class.new(connections: 2, connections_per_second: 10, max_concurrent_connections: 1, verbose: true, jitter: 0.0) }

    context 'when ratelimiting connections' do
      before do
        allow(client_rate).to receive(:execute_connection)
        allow(client_rate).to receive(:trap).with('INT')
        # Architectural limitation: Async::Task yielded internally
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Async::Task).to receive(:sleep)
        # rubocop:enable RSpec/AnyInstance
        client_rate.start
      end

      it 'calls execute_connection for index 0', :rspec do
        expect(client_rate).to have_received(:execute_connection).with(0)
      end

      it 'calls execute_connection for index 1', :rspec do
        expect(client_rate).to have_received(:execute_connection).with(1)
      end
    end

    context 'when testing sleep exactly' do
      # Architectural limitation: Async::Task yielded internally
      # rubocop:disable RSpec/AnyInstance
      it 'sleeps correctly', :rspec do
        allow(client_rate).to receive(:execute_connection)
        allow(client_rate).to receive(:trap).with('INT')
        expect_any_instance_of(Async::Task).to receive(:sleep).with(0.1).twice
        client_rate.start
      end
      # rubocop:enable RSpec/AnyInstance
    end

    context 'when providing ramp_up delay' do
      let(:client_ramp) { described_class.new(connections: 4, ramp_up: 10.0, max_concurrent_connections: 4, verbose: true, jitter: 0.0) }

      before do
        allow(client_ramp).to receive(:execute_connection)
        allow(client_ramp).to receive(:trap).with('INT')
      end

      # Architectural limitation: Async::Task mock needed
      # rubocop:disable RSpec/AnyInstance
      it 'calculates delay properly overriding connections_per_second', :rspec do
        expect_any_instance_of(Async::Task).to receive(:sleep).with(2.5).exactly(4).times
        client_ramp.start
      end

      it 'calls execute_connection exact times', :rspec do
        # We need another stub for Async task sleep or ignore it here:
        allow_any_instance_of(Async::Task).to receive(:sleep)
        client_ramp.start
        expect(client_ramp).to have_received(:execute_connection).exactly(4).times
      end
      # rubocop:enable RSpec/AnyInstance
    end

    context 'when no ramp_up or rate limits configured' do
      let(:client_zero) { described_class.new(connections: 1, ramp_up: 0.0, connections_per_second: 0) }

      it 'calculates 0.0 delay directly', :rspec do
        allow(client_zero).to receive(:execute_connection)
        allow(client_zero).to receive(:trap).with('INT')
        allow(client_zero).to receive(:calculate_sleep).and_call_original
        expect_any_instance_of(Async::Task).not_to receive(:sleep)
        client_zero.start
      end
    end

    it 'maps MULTIPLE TARGETS labels effectively inside start' do
      client_multi = described_class.new(connections: 1, target_urls: ['http://a', 'http://b'])
      allow(client_multi).to receive(:trap).with('INT')
      allow(client_multi).to receive(:execute_connection)
      expect { client_multi.start }.to output(/2 TARGETS/).to_stdout
    end
  end

  describe 'internal execution helpers' do
    let(:client) { described_class.new(connections: 1, read_timeout: 5.0, user_agent: 'TestAgent') }

    context 'when targeting http locally' do
      it 'initializes protocol label correctly', :rspec do
        expect(client.instance_variable_get(:@protocol_label)).to eq('HTTP')
      end

      it 'initializes uri correctly', :rspec do
        expect(client.instance_variable_get(:@target_contexts).first[:uri].to_s).to eq('http://localhost:8080')
      end

      it 'initializes timeout correctly', :rspec do
        expect(client.instance_variable_get(:@target_contexts).first[:http_args]).to include(read_timeout: 5.0)
      end

      it 'executes the connection safely and closes if not reopening', :rspec do
        allow(client).to receive(:run_http_session)
        allow(client).to receive(:sleep)
        client.send(:execute_connection, 0)
        expect(client).to have_received(:run_http_session).with(0, anything)
      end
    end

    context 'when Addrinfo resolution explicitly fails' do
      let(:client_dns) { described_class.new(connections: 1, target_urls: ['http://broken.local']) }

      it 'rescues SocketError gracefully keeping args cleanly mapped', :rspec do
        allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError)
        contexts = client_dns.send(:build_target_contexts)
        expect(contexts.first[:http_args][:ipaddr]).to be_nil
      end

      it 'handles empty Addrinfo completely safely resolving to nil inherently' do
        allow(Addrinfo).to receive(:getaddrinfo).and_return([])
        client_blank = described_class.new(connections: 1)
        expect(client_blank.send(:build_target_contexts).first[:http_args][:ipaddr]).to be_nil
      end
    end

    context 'when determining protocol label' do
      it 'maps HTTPS properly', :rspec do
        client_https = described_class.new(connections: 1, target_urls: [], use_https: true)
        expect(client_https.send(:determine_protocol_label)).to eq('HTTPS')
      end

      it 'maps EXTERNAL single target correctly', :rspec do
        client_ext = described_class.new(connections: 1, target_urls: ['https://remote.com'])
        expect(client_ext.send(:determine_protocol_label)).to eq('EXTERNAL HTTPS')
      end

      it 'handles implicit typings cleanly without scheme gracefully' do
        client_blank = described_class.new(connections: 1, target_urls: ['//remote.com'])
        expect(client_blank.send(:determine_protocol_label)).to eq('EXTERNAL ')
      end
    end

    context 'when reopening connections' do
      let(:client) { described_class.new(connections: 1, reopen_closed_connections: true, reopen_interval: 0.1, jitter: 0.0) }

      before do
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
      end

      it 'reopens and sleeps interval', :rspec do
        expect(client).to have_received(:sleep).with(0.1)
      end
    end

    context 'when calculate_sleep works with jitter' do
      let(:client) { described_class.new(connections: 1, jitter: 0.5) }

      it 'randomizes sleep mathematically within variance', :rspec do
        allow(client).to receive(:rand).with(-2.5..2.5).and_return(1.0)
        expect(client.send(:calculate_sleep, 5.0)).to eq(6.0)
      end
    end
  end

  describe 'run_http_session' do
    context 'when having keep_alive_timeout and no ping' do
      let(:client) { described_class.new(connections: 1, keep_alive_timeout: 0.1, ping: false) }

      before do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess, read_body: nil)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request).and_yield(mock_response)
        allow(client).to receive(:sleep)

        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time + 0.2)
      end

      it 'rescues explicitly without crashing logically' do
        expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      end
    end

    context 'when Net::HTTP cleanly does not respond natively to max_retries_assignment' do
      it 'handles Net::HTTP lacking natively max_retries assignments safely' do
        mock_http = double('Net::HTTP', request: nil)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:respond_to?).with(:max_retries=).and_return(false)
        client = described_class.new(connections: 1, keep_alive_timeout: 0.1, jitter: 0.0)
        allow(client).to receive(:sleep)
        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time + 0.2)
        expect { client.send(:run_http_session, 0, time) }.not_to raise_error
      end

      it 'handles Net::HTTP responding authentically actively setting assignment seamlessly' do
        mock_http = double('Net::HTTP', request: nil)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:respond_to?).with(:max_retries=).and_return(true)
        allow(mock_http).to receive(:max_retries=).with(0)
        client = described_class.new(connections: 1, keep_alive_timeout: 0.1, jitter: 0.0)
        allow(client).to receive(:sleep)
        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time + 0.2)
        client.send(:run_http_session, 0, time)
        expect(mock_http).to have_received(:max_retries=).with(0)
      end
    end

    context 'when running actively single sequence natively mapping' do
      let(:client) { described_class.new(connections: 2, bind_ips: ['192.168.1.1', '192.168.1.2'], keep_alive_timeout: 0.1) }

      before do
        mock_http = instance_double(Net::HTTP)
        allow(mock_http).to receive(:request)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      end

      it 'uses index 0 address locally first' do
        client.send(:run_http_session, 0, Time.now)
        expect(Net::HTTP).to have_received(:start).with('localhost', 8080, hash_including(local_host: '192.168.1.1'))
      end

      it 'uses index 1 address locally second' do
        client.send(:run_http_session, 1, Time.now)
        expect(Net::HTTP).to have_received(:start).with('localhost', 8080, hash_including(local_host: '192.168.1.2'))
      end
    end

    context 'when proxy_pool configured' do
      let(:client) { described_class.new(connections: 2, proxy_pool: ['http://proxy1:80', 'http://user:pass@proxy2:81'], keep_alive_timeout: 0.1) }

      before do
        mock_http = instance_double(Net::HTTP)
        allow(mock_http).to receive(:request)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
      end

      it 'uses proxy 0 first' do
        client.send(:run_http_session, 0, Time.now)
        expect(Net::HTTP).to have_received(:start).with('localhost', 8080, hash_including(proxy_address: 'proxy1', proxy_port: 80))
      end

      it 'uses proxy 1 second with auth' do
        client.send(:run_http_session, 1, Time.now)
        proxy2_args = hash_including(proxy_address: 'proxy2', proxy_port: 81, proxy_user: 'user', proxy_pass: 'pass')
        expect(Net::HTTP).to have_received(:start).with('localhost', 8080, proxy2_args)
      end
    end

    context 'when custom headers present' do
      let(:client) { described_class.new(connections: 1, ping: false, headers: { 'Auth' => 'B', 'XC' => 'V' }, keep_alive_timeout: 0.1) }
      let(:captured_request) do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        caught_req = nil
        allow(mock_http).to receive(:request) { |req| caught_req = req }
        allow(client).to receive(:sleep)
        client.send(:run_http_session, 0, Time.now)
        caught_req
      end

      it 'injects Auth header' do
        expect(captured_request['Auth']).to eq('B')
      end

      it 'injects XC header' do
        expect(captured_request['XC']).to eq('V')
      end
    end

    context 'when qps_per_connection active' do
      let(:client) { described_class.new(connections: 1, ping: false, keep_alive_timeout: 0.0, qps_per_connection: 10, jitter: 0.0) }

      before do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess, is_a?: false, read_body: nil)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |_req, &block|
          block&.call(mock_response)
          mock_response
        end
        allow(client).to receive(:sleep)
        client.send(:run_http_session, 0, Time.now)
      end

      it 'sleeps correctly based on qps delay' do
        expect(client).to have_received(:sleep).with(0.1)
      end
    end

    context 'when qps_per_connection receives server error' do
      let(:client) { described_class.new(connections: 1, ping: false, keep_alive_timeout: 0.0, track_status_codes: true, qps_per_connection: 10, jitter: 0.0) }

      before do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPBadGateway, is_a?: false, read_body: nil, code: '502')
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |_req, &block|
          block&.call(mock_response)
          mock_response
        end
        allow(client).to receive(:sleep)
        allow(client).to receive(:log_info)
        client.send(:run_http_session, 0, Time.now)
      end

      it 'logs HTTP 502 dynamically for drops', :rspec do
        expect(client).to have_received(:log_info).with(/Upstream returned HTTP 502/)
      end
    end

    context 'when qps connection executes cleanly sequentially seamlessly', :rspec do
      let(:client_qps) { described_class.new(connections: 1, ping: false, qps_per_connection: 10, keep_alive_timeout: 0.1, jitter: 0.0) }
      it 'loops successfully and hits mathematically target duration boundaries' do
        mock_http = instance_double(Net::HTTP)
        mock_success = instance_double(Net::HTTPSuccess, is_a?: true, read_body: nil)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |_req, &block|
          block&.call(mock_success)
          mock_success
        end
        allow(client_qps).to receive(:sleep)
        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time + 0.2)
        expect { client_qps.send(:run_http_session, 0, time) }.not_to raise_error
      end
    end

    context 'when using slowloris_delay' do
      let(:client) { described_class.new(connections: 1, ping: false, slowloris_delay: 1.0, keep_alive_timeout: 0.0, jitter: 0.0) }
      let(:mock_io) { instance_double(IO, write: 1, flush: nil) }
      let(:mock_socket_wrapper) { double('SocketWrapper', io: mock_io) }

      before do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:instance_variable_get).with(:@socket).and_return(mock_socket_wrapper)
        allow(client).to receive(:sleep)
        allow(client).to receive(:loop).and_yield
        client.send(:run_http_session, 0, Time.now)
      end

      it 'forces byte-by-byte socket writes', :rspec do
        expect(mock_io).to have_received(:write).at_least(:once)
      end

      it 'forces flush on the socket', :rspec do
        expect(mock_io).to have_received(:flush).at_least(:once)
      end
    end

    context 'when slowloris loop hits timeout limit' do
      let(:client) { described_class.new(connections: 1, ping: false, slowloris_delay: 1.0, keep_alive_timeout: 0.1, jitter: 0.0) }
      let(:mock_io) { instance_double(IO, write: 1, flush: nil) }
      let(:mock_socket_wrapper) { double('SocketWrapper', io: mock_io) }

      before do
        mock_http = instance_double(Net::HTTP)
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:instance_variable_get).with(:@socket).and_return(mock_socket_wrapper)
        allow(client).to receive(:sleep)
        allow(client).to receive(:log_info)

        time = Time.now
        allow(Time).to receive(:now).and_return(time)
        # Yield start manually to fake the timeline loop iteration securely
      end

      it 'logs gracefully and breaks the eternal loop', :rspec do
        # Enforce exact simulated elapsed time
        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time, time + 0.2)
        client.send(:run_http_session, 0, time)
        expect(client).to have_received(:log_info).with(/Keep-alive timeout reached, closing Slowloris thread/)
      end
    end

    context 'when slowloris paths execute elegantly natively' do
      it 'returns natively seamlessly if socket is utterly missing mathematically' do
         client_sl = described_class.new(connections: 1, slowloris_delay: 1.0, keep_alive_timeout: 0.1)
         mock_http = instance_double(Net::HTTP)
         allow(mock_http).to receive(:instance_variable_get).with(:@socket).and_return(nil)
         expect { client_sl.send(:run_slowloris_session, 0, URI('/'), mock_http, Time.now) }.not_to raise_error
      end

      it 'maps paths solidly using literal endpoints resolving seamlessly', :rspec do
        client_sl = described_class.new(connections: 1, slowloris_delay: 1.0, jitter: 0.0, keep_alive_timeout: 0.1)
        mock_io = instance_double(IO, write: 1, flush: nil)
        mock_wrapper = double('SocketWrapper', io: mock_io)
        mock_http = instance_double(Net::HTTP)
        allow(mock_http).to receive(:instance_variable_get).with(:@socket).and_return(mock_wrapper)
        
        time = Time.now
        allow(Time).to receive(:now).and_return(time, time, time + 0.5)
        allow(client_sl).to receive(:sleep)
        
        uri = URI('http://local/test?a=1')
        client_sl.send(:run_slowloris_session, 0, uri, mock_http, time)
        
        expect(mock_io).to have_received(:write).at_least(:once)
      end
    end

    context 'when pinging actively' do
      let(:client) { described_class.new(connections: 1, ping: true, ping_period: 1, keep_alive_timeout: 0.0, jitter: 0.0) }

      before do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess, is_a?: false, read_body: nil)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |req, &block|
          block&.call(mock_response) if req.is_a?(Net::HTTP::Get)
          mock_response
        end

        allow(client).to receive(:sleep)
        client.send(:run_http_session, 0, Time.now)
      end

      it 'sleeps exactly ping_period after pinging' do
        expect(client).to have_received(:sleep).with(1.0)
      end
    end

    context 'when ping actively succeeds cleanly natively', :rspec do
      let(:client_ping) { described_class.new(connections: 1, ping: true, ping_period: 1, keep_alive_timeout: 0.1, jitter: 0.0) }
      it 'loops perfectly returning HTTPSuccess naturally dropping out on duration break' do
          mock_http = instance_double(Net::HTTP)
          mock_success = instance_double(Net::HTTPSuccess, is_a?: true)
          allow(Net::HTTP).to receive(:start).and_yield(mock_http)
          allow(mock_http).to receive(:request).and_return(mock_success)
          allow(client_ping).to receive(:sleep)
          time = Time.now
          allow(Time).to receive(:now).and_return(time, time, time + 0.2)
          expect { client_ping.send(:run_http_session, 0, time) }.not_to raise_error
      end
    end

    context 'when pinging and status codes actively tested' do
      let(:client) { described_class.new(connections: 1, ping: true, ping_period: 1, keep_alive_timeout: 0.0, track_status_codes: true) }

      before do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPTooManyRequests, read_body: nil, is_a?: false, code: '429')
        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |req, &block|
          block&.call(mock_response) if req.is_a?(Net::HTTP::Get)
          mock_response
        end
        allow(client).to receive(:sleep)
        allow(client).to receive(:log_info)
        client.send(:run_http_session, 0, Time.now)
      end

      it 'logs 429 status on non-success' do
        expect(client).to have_received(:log_info).with(/Upstream returned HTTP 429/)
      end

      it 'logs connection established' do
        expect(client).to have_received(:log_info).with(/Connection established/)
      end

      it 'logs connection gracefully closed' do
        expect(client).to have_received(:log_info).with(/Connection gracefully closed/)
      end
    end
  end

  describe 'error rescuing' do
    let(:client) { described_class.new(connections: 1) }

    it 'rescues EMFILE', :rspec do
      allow(File).to receive(:open).and_call_original
      allow(Net::HTTP).to receive(:start).and_raise(Errno::EMFILE, 'Too many open files')
      expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      client.instance_variable_get(:@log_queue) << :terminate
      client.instance_variable_get(:@logger_thread).join
    end

    it 'rescues EADDRNOTAVAIL', :rspec do
      allow(File).to receive(:open).and_call_original
      allow(Net::HTTP).to receive(:start).and_raise(Errno::EADDRNOTAVAIL)
      expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      client.instance_variable_get(:@log_queue) << :terminate
      client.instance_variable_get(:@logger_thread).join
    end

    it 'rescues generic standard errors', :rspec do
      allow(File).to receive(:open).and_call_original
      allow(Net::HTTP).to receive(:start).and_raise(StandardError, 'Misc failure')
      expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      client.instance_variable_get(:@log_queue) << :terminate
      client.instance_variable_get(:@logger_thread).join
    end
  end

  describe 'logging behaviour' do
    let(:verbose_client) { described_class.new(connections: 1, verbose: true) }
    let(:quiet_client) { described_class.new(connections: 1, verbose: false) }

    it 'logs info into queue when verbose configured' do
      verbose_client.instance_variable_get(:@logger_thread).kill
      verbose_client.send(:log_info, 'test_message')
      expect(verbose_client.instance_variable_get(:@log_queue).pop[1]).to match(/test_message/)
    end

    it 'skips pushing to queue when not verbose' do
      quiet_client.instance_variable_get(:@logger_thread).kill
      quiet_client.send(:log_info, 'test_message')
      expect(quiet_client.instance_variable_get(:@log_queue).size).to eq(0)
    end

    it 'flushes info and error logs securely to file', :rspec do
      log_file_stub = instance_double(File, puts: nil, flush: nil)
      err_file_stub = instance_double(File, puts: nil, flush: nil)
      allow(File).to receive(:open).with(/\/client\.log/, 'a').and_yield(log_file_stub)
      allow(File).to receive(:open).with(/\/client\.err/, 'a').and_yield(err_file_stub)
      
      verbose_client.instance_variable_get(:@log_queue) << [:info, 'test_info']
      verbose_client.instance_variable_get(:@log_queue) << [:error, 'test_error']
      verbose_client.instance_variable_get(:@log_queue) << [:unknown_type, 'ignored payload']
      verbose_client.instance_variable_get(:@log_queue) << :terminate
      verbose_client.instance_variable_get(:@logger_thread).join

      expect(log_file_stub).to have_received(:puts).with('test_info')
      expect(log_file_stub).to have_received(:flush)
      expect(err_file_stub).to have_received(:puts).with('test_error')
      expect(err_file_stub).to have_received(:flush)
    end
  end
end
