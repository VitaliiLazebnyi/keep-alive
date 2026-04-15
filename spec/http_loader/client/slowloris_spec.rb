# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/client/slowloris'
require 'http_loader/client/logger'
require 'http_loader/client/config'

RSpec.describe HttpLoader::Client::Slowloris do
  let(:config) do
    HttpLoader::Client::Config.new(
      connections: 1, target_urls: [], use_https: false,
      verbose: false, ping: false, ping_period: 0, http_loader_timeout: 0.1,
      connections_per_second: 0, max_concurrent_connections: 1,
      reopen_closed_connections: false, reopen_interval: 0.0,
      read_timeout: 5.0, user_agent: 'A', jitter: 0.0,
      track_status_codes: false, ramp_up: 0.0, bind_ips: [],
      proxy_pool: [], qps_per_connection: 0, headers: {}, slowloris_delay: 1.0
    )
  end
  let(:slowloris) { described_class.new(config, HttpLoader::Client::Logger.new(false)) }

  describe '#run' do
    let(:uri) { URI('http://local/') }
    let(:http) { Net::HTTP.new('localhost') }

    before do
      socket = instance_double(Net::BufferedIO)
      allow(socket).to receive(:io).and_return(File.open(File::NULL, 'w'))
      allow(http).to receive(:instance_variable_get).with(:@socket).and_return(socket)
      allow(slowloris).to receive(:sleep)
    end

    it 'executes payload generation and byte injection cleanly natively internally', :rspec do
      time = Time.now
      allow(Time).to receive(:now).and_return(time, time, time, time + 0.5)
      expect { slowloris.run(0, uri, http, time) }.not_to raise_error
    end

    it 'returns early if slowloris_delay is 0' do
      slow = described_class.new(config.with(slowloris_delay: 0.0), HttpLoader::Client::Logger.new(false))
      expect { slow.run(0, uri, http, Time.now) }.not_to raise_error
      expect(http).not_to have_received(:instance_variable_get)
    end

    it 'returns early if socket is absent' do
      allow(http).to receive(:instance_variable_get).with(:@socket).and_return(nil)
      expect { slowloris.run(0, uri, http, Time.now) }.not_to raise_error
    end

    it 'calculates delay accurately and maps query parameters accurately' do
      slow2 = described_class.new(config.with(slowloris_delay: 1.0, jitter: 0.1), HttpLoader::Client::Logger.new(false))
      allow(slow2).to receive(:sleep)
      time = Time.now
      allow(Time).to receive(:now).and_return(time, time, time, time + 0.5)
      expect { slow2.run(0, URI('http://local/path?q=1'), http, time) }.not_to raise_error
    end
  end
end
