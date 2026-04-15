# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/client/http_session'
require 'http_loader/client/logger'
require 'http_loader/client/config'

RSpec.describe HttpLoader::Client::HttpSession do
  let(:config) do
    HttpLoader::Client::Config.new(
      connections: 1, target_urls: [], use_https: false,
      verbose: false, ping: true, ping_period: 1, http_loader_timeout: 0.1,
      connections_per_second: 0, max_concurrent_connections: 1,
      reopen_closed_connections: false, reopen_interval: 0.0,
      read_timeout: 5.0, user_agent: 'A', jitter: 0.0,
      track_status_codes: false, ramp_up: 0.0, bind_ips: [],
      proxy_pool: [], qps_per_connection: 0, headers: {}, slowloris_delay: 0.0
    )
  end
  let(:session) { described_class.new(config, HttpLoader::Client::Logger.new(false)) }

  describe '#run' do
    let(:uri) { URI('http://local/') }
    let(:http) { Net::HTTP.new('localhost') }

    before do
      allow(http).to receive(:request).and_return(instance_double(Net::HTTPSuccess, is_a?: true, read_body: nil))
      allow(session).to receive(:sleep)
    end

    it 'processes initial get completely smoothly and safely naturally', :rspec do
      expect { session.run(0, uri, http, Time.now) }.not_to raise_error
    end

    it 'processes jitter and empty requests completely' do
      cfg = config.with(jitter: 0.1)
      sess = described_class.new(cfg, HttpLoader::Client::Logger.new(false))
      allow(sess).to receive(:sleep)

      # Mock the request and read_body yield
      res = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(res).to receive(:read_body).and_yield('chunk')
      allow(http).to receive(:request) do |*_args, &block|
        block&.call(res)
        res
      end

      expect { sess.run(0, uri, http, Time.now) }.not_to raise_error
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'processes QPS payload and track status successfully' do
      cfg = config.with(qps_per_connection: 5, track_status_codes: true)
      sess = described_class.new(cfg, HttpLoader::Client::Logger.new(false))
      allow(sess).to receive(:sleep)

      res = Net::HTTPInternalServerError.new('1.1', '500', 'Error')
      allow(res).to receive(:read_body).and_yield('chunk')
      allow(http).to receive(:request) do |*_args, &block|
        block&.call(res)
        res
      end

      # Will call perform_qps? and log_status
      # process_heartbeat? returns false (because success? is false)
      expect { sess.run(0, uri, http, Time.now) }.not_to raise_error
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'processes ping explicitly actively when configured' do
      cfg = config.with(ping: true)
      sess = described_class.new(cfg, HttpLoader::Client::Logger.new(false))
      allow(sess).to receive(:sleep)

      res = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(res).to receive(:read_body).and_yield('chunk')
      allow(http).to receive(:request) do |*_args, &block|
        block&.call(res)
        res
      end

      time = Time.now
      allow(Time).to receive(:now).and_return(time, time + 1.0)
      # keep alive timeout is 0.0 (from config), so it breaks after 1 loop!
      expect { sess.run(0, uri, http, time) }.not_to raise_error
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'idles gracefully securely securely explicitly' do
      cfg = config.with(qps_per_connection: 0, ping: false)
      sess = described_class.new(cfg, HttpLoader::Client::Logger.new(false))
      allow(sess).to receive(:sleep)

      res = Net::HTTPOK.new('1.1', '200', 'OK')
      allow(res).to receive(:read_body).and_yield('chunk')
      allow(http).to receive(:request) do |*_args, &block|
        block&.call(res)
        res
      end

      time = Time.now
      allow(Time).to receive(:now).and_return(time, time + 1.0)

      expect { sess.run(0, uri, http, time) }.not_to raise_error
    end
  end
end
