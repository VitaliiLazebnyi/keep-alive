# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/harness'

RSpec.describe HttpLoader::Harness::Formatter do
  let(:dummy_class) do
    Class.new(HttpLoader::Harness) do
      def initialize(config)
        super
        @config = config
      end
    end
  end

  let(:config) { HttpLoader::Harness::Config.new(target_urls: [], connections: 1, use_https: false, client_args: [], export_json: nil) }
  let(:harness) { dummy_class.new(config) }

  before do
    allow($stdout).to receive(:puts)
  end

  describe '#print_table_header' do
    it 'prints gracefully cleanly natively' do
      expect { harness.print_table_header }.to output(/Monitoring resources/).to_stdout
    end
  end

  describe '#print_startup_banner' do
    it 'maps HTTP successfully' do
      harness.print_startup_banner
      expect($stdout).to have_received(:puts).with(/HTTP/)
    end

    it 'maps HTTPS successfully natively' do
      harness.instance_variable_set(:@config, config.with(use_https: true))
      harness.print_startup_banner
      expect($stdout).to have_received(:puts).with(/HTTPS/)
    end

    it 'maps EXTERNAL URL securely smoothly natively' do
      harness.instance_variable_set(:@config, config.with(target_urls: ['http://local']))
      harness.print_startup_banner
      expect($stdout).to have_received(:puts).with(/EXTERNAL URL/)
    end

    it 'maps MULTIPLE TARGETS natively correctly gracefully' do
      harness.instance_variable_set(:@config, config.with(target_urls: ['http://a', 'http://b']))
      harness.print_startup_banner
      expect($stdout).to have_received(:puts).with(/MULTIPLE TARGETS/)
    end
  end

  describe '#format_kb_conn' do
    it 'returns EXTERNAL when pid is nil' do
      expect(harness.format_kb_conn(10.0, 1, nil)).to eq('EXTERNAL')
    end

    it 'returns N/A when connections zero or negative' do
      expect(harness.format_kb_conn(10.0, 0, 123)).to eq('N/A')
      expect(harness.format_kb_conn(10.0, -1, 123)).to eq('N/A')
    end

    it 'calculates gracefully mathematically identically securely' do
      expect(harness.format_kb_conn(1024.0, 4, 123)).to eq('256.0 KB')
    end
  end

  describe '#print_combined_stats' do
    it 'formats logs elegantly outputting gracefully' do
      # We just need to mock monitor and pm and test execution
      monitor = instance_double(HttpLoader::Harness::ResourceMonitor)
      allow(monitor).to receive_messages(process_stats: ['1.0', '10MB', 10_240.0, 2], count_established_connections: 0)
      harness.instance_variable_set(:@monitor, monitor)

      pm = instance_double(HttpLoader::Harness::ProcessManager, server_pid: 1, client_pid: 2)
      harness.instance_variable_set(:@pm, pm)

      harness.print_combined_stats(1, '2.0', 3, '5MB')
      expect($stdout).to have_received(:puts).with(/1\.0/)
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'formats external safely securely cleanly natively' do
      monitor = instance_double(HttpLoader::Harness::ResourceMonitor)
      allow(monitor).to receive_messages(process_stats: ['1.0', '10MB', 10_240.0, 2], count_established_connections: 0)
      harness.instance_variable_set(:@monitor, monitor)

      pm = instance_double(HttpLoader::Harness::ProcessManager, server_pid: nil, client_pid: 2)
      harness.instance_variable_set(:@pm, pm)

      harness.print_combined_stats(1, '2.0', 3, '5MB')
      expect($stdout).to have_received(:puts).with(/EXTERNAL/)
    end
  end

  describe '#extract_client_stats' do # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'extracts client organically successfully seamlessly dynamically' do
      monitor = instance_double(HttpLoader::Harness::ResourceMonitor)
      allow(monitor).to receive_messages(process_stats: ['1.0', '10MB', 10_240.0, 2], count_established_connections: 5)
      harness.instance_variable_set(:@monitor, monitor)

      pm = instance_double(HttpLoader::Harness::ProcessManager, server_pid: 1, client_pid: 2)
      harness.instance_variable_set(:@pm, pm)

      expect(harness.send(:extract_client_stats)).to eq([5, '1.0', 2, '10MB'])
    end
  end
end
