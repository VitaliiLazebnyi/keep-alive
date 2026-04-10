# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'async'
require 'keep_alive/client'

RSpec.describe KeepAlive::Client do
  let(:connections) { 1 }

  before do
    allow($stdout).to receive(:puts)
    allow(File).to receive(:write)
    allow(File).to receive(:open)
  end

  describe '#start' do
    let(:client) { described_class.new(connections: 2, connections_per_second: 10, max_concurrent_connections: 1, verbose: true) }

    it 'executes Async logic with semaphore and ratelimiting', rspec: true do
      expect(client).to receive(:execute_connection).with(0)
      expect(client).to receive(:execute_connection).with(1)

      # Mock trap to avoid exiting test suite
      allow(client).to receive(:trap).with('INT')

      # Should sleep for ratelimiting
      expect_any_instance_of(Async::Task).to receive(:sleep).with(0.1).twice

      client.start
    end

    context 'when targeting http locally' do
      let(:client) { described_class.new(connections: 1, read_timeout: 5.0, user_agent: 'TestAgent') }

      it 'initializes generic http target correctly', rspec: true do
        expect(client.instance_variable_get(:@protocol_label)).to eq('HTTP')
        expect(client.instance_variable_get(:@uri).to_s).to eq('http://localhost:8080')
        expect(client.instance_variable_get(:@http_args)).to eq({ read_timeout: 5.0 })
      end

      it 'executes the connection safely and closes if not reopening', rspec: true do
        # Testing loop in execute_connection breaks unless reopen_closed_connections
        expect(client).to receive(:run_http_session).with(0, anything)
        expect(client).not_to receive(:sleep) # won't sleep reopen interval if not reopening
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

    context 'run_http_session' do
      let(:client) { described_class.new(connections: 1, keep_alive_timeout: 0.1, ping: false) }

      it 'respects keep alive timeout without pinging' do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |_, &block|
          block&.call(mock_response)
          mock_response
        end
        allow(mock_response).to receive(:read_body)

        allow(client).to receive(:sleep)

        # Inject elapsed mocking
        time = Time.now
        # start_time = time
        # elapsed first 0
        allow(Time).to receive(:now).and_return(time, time, time + 0.2)

        client.send(:run_http_session, 0, time)
        # no loop error due to break
      end
    end

    context 'run_http_session with pinging' do
      let(:client) { described_class.new(connections: 1, ping: true, ping_period: 1, keep_alive_timeout: 0) }

      it 'pings' do
        mock_http = instance_double(Net::HTTP)
        mock_response = instance_double(Net::HTTPSuccess)

        allow(Net::HTTP).to receive(:start).and_yield(mock_http)
        allow(mock_http).to receive(:request) do |req, &block|
          block&.call(mock_response) if req.is_a?(Net::HTTP::Get)
          mock_response
        end
        allow(mock_response).to receive(:read_body)
        allow(mock_response).to receive(:is_a?).and_return(false) # simulate failed ping to break loop

        allow(client).to receive(:sleep)
        client.send(:run_http_session, 0, Time.now)
        expect(client).to have_received(:sleep).with(1)
      end
    end

    context 'when erroring with EMFILE' do
      let(:client) { described_class.new(connections: 1) }
      it 'rescues and buffers the error to Mutex sync log', rspec: true do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::EMFILE, 'Too many open files')
        expect(File).to receive(:open).with('client.err', 'a')
        expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      end
    end

    context 'when erroring with EADDRNOTAVAIL' do
      let(:client) { described_class.new(connections: 1) }
      it 'rescues and buffers the error', rspec: true do
        allow(Net::HTTP).to receive(:start).and_raise(Errno::EADDRNOTAVAIL)
        expect(File).to receive(:open).with('client.err', 'a')
        expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      end
    end

    context 'when erroring generally' do
      let(:client) { described_class.new(connections: 1) }
      it 'rescues generic standard errors', rspec: true do
        allow(Net::HTTP).to receive(:start).and_raise(StandardError, 'Misc failure')
        expect(File).to receive(:open).with('client.err', 'a')
        expect { client.send(:run_http_session, 0, Time.now) }.not_to raise_error
      end
    end
  end
end
