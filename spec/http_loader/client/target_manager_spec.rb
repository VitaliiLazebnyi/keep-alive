# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/client/target_manager'
require 'http_loader/client/config'

RSpec.describe HttpLoader::Client::TargetManager do
  let(:config) do
    HttpLoader::Client::Config.new(
      connections: 1, target_urls: ['http://local'], use_https: false,
      verbose: false, ping: false, ping_period: 0, http_loader_timeout: 0.0,
      connections_per_second: 0, max_concurrent_connections: 1,
      reopen_closed_connections: false, reopen_interval: 0.0,
      read_timeout: 5.0, user_agent: 'A', jitter: 0.0,
      track_status_codes: false, ramp_up: 0.0, bind_ips: [],
      proxy_pool: [], qps_per_connection: 0, headers: {}, slowloris_delay: 0.0
    )
  end

  let(:manager) { described_class.new(config) }

  describe '#protocol_label' do
    it 'maps labels securely based on singular url endpoints', :rspec do
      expect(manager.protocol_label).to eq('EXTERNAL HTTP')
    end

    it 'maps MULTIPLE TARGETS properly' do
      m = described_class.new(config.with(target_urls: ['http://a', 'http://b']))
      expect(m.protocol_label).to eq('MULTIPLE TARGETS (2)')
    end

    it 'maps HTTPS explicitly when no target_urls are provided' do
      m = described_class.new(config.with(target_urls: [], use_https: true))
      expect(m.protocol_label).to eq('HTTPS')
    end

    it 'maps HTTP explicitly when no target_urls are provided' do
      m = described_class.new(config.with(target_urls: [], use_https: false))
      expect(m.protocol_label).to eq('HTTP')
    end
  end

  describe '#contexts' do
    it 'evaluates and resolves IP statically through Addrinfo flawlessly', :rspec do
      allow(Addrinfo).to receive(:getaddrinfo).and_return([])
      expect(manager.contexts.first[:http_args][:ipaddr]).to be_nil
    end

    it 'evaluates SocketError exceptions handling effectively' do
      allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError)
      expect(manager.contexts.first[:http_args][:ipaddr]).to be_nil
    end

    it 'merges secure_opts correctly when scheme is HTTPS' do
      m = described_class.new(config.with(target_urls: ['https://secure']))
      expect(m.contexts.first[:http_args][:use_ssl]).to be(true)
    end
  end

  describe '#context_for' do
    it 'fetches modulus index cleanly' do
      expect(manager.context_for(5)[:uri].host).to eq('local')
    end
  end

  describe '#http_opts_for' do
    let(:config_proxy) { config.with(proxy_pool: ['http://proxy.com', 'http://proxy.com:8080']) }
    let(:manager_proxy) { described_class.new(config_proxy) }

    it 'maps proxy parameters natively seamlessly via url mapping mechanics', :rspec do
      opts = manager_proxy.http_opts_for(0, {})
      expect(opts[:proxy_address]).to eq('proxy.com')
      expect(opts[:proxy_user]).to be_nil
    end

    it 'maps proxy parameters natively with authentication and bind_ips' do
      cfg = config.with(proxy_pool: ['http://u:p@proxy.com'], bind_ips: ['1.1.1.1'])
      mgr = described_class.new(cfg)
      opts = mgr.http_opts_for(0, {})
      expect(opts[:proxy_user]).to eq('u')
      expect(opts[:proxy_pass]).to eq('p')
      expect(opts[:local_host]).to eq('1.1.1.1')
    end
  end
end
