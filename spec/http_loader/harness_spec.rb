# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe HttpLoader::Harness do
  let(:config) { HttpLoader::Harness::Config.new(connections: 1, target_duration: 1.0, target_urls: ['http://localhost'], export_json: 'logs/telemetry.json') }
  let(:harness) { described_class.new(config) }

  before do
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow_any_instance_of(HttpLoader::Harness::ProcessManager).to receive(:spawn_processes)
    allow_any_instance_of(HttpLoader::Harness::ProcessManager).to receive(:cleanup)
    allow_any_instance_of(HttpLoader::Harness::ProcessManager).to receive(:missing_process?).and_return(false)
    allow_any_instance_of(HttpLoader::Harness::Telemetry).to receive(:export!)
    allow_any_instance_of(HttpLoader::Harness::Telemetry).to receive(:check_bottlenecks!)
  end

  describe '#run_lifecycle with SIGINT' do
    it 'traps INT cleanly' do
      allow(harness.instance_variable_get(:@pm)).to receive(:spawn_processes)
      allow(harness.instance_variable_get(:@pm)).to receive(:cleanup)
      allow(harness).to receive(:monitor_resources)
      allow(harness).to receive(:trap).with('INT').and_yield
      allow(harness).to receive(:exit).with(0)

      expect { harness.send(:run_lifecycle) }.to output(/Caught interrupt/).to_stdout
      expect(harness.instance_variable_get(:@pm)).to have_received(:cleanup).twice
    end
  end

  describe '#start' do
    it 'dispatches start correctly mapping lifecycle gracefully' do
      allow(harness).to receive(:print_startup_banner)
      allow(harness).to receive(:bump_file_limits)
      allow(harness).to receive(:run_lifecycle)

      harness.start
      expect(harness).to have_received(:run_lifecycle)
    end
  end

  describe '#run_lifecycle' do
    it 'spawns processes and monitors resources' do
      allow(harness).to receive(:trap).with('INT')
      allow(harness).to receive(:monitor_resources)

      harness.send(:run_lifecycle)
      expect(harness).to have_received(:monitor_resources)
    end

    it 'ensures telemetry and cleanup export safely when errors trigger' do
      allow(harness).to receive(:trap)
      allow(harness).to receive(:monitor_resources).and_raise(StandardError)

      expect { harness.send(:run_lifecycle) }.to raise_error(StandardError)
      expect(harness.instance_variable_get(:@telemetry)).to have_received(:export!)
    end
  end

  describe '#monitor_resources' do
    it 'ticks and breaks properly' do
      allow(harness).to receive(:print_table_header)
      allow(harness).to receive(:duration_exceeded?).and_return(false, true)
      allow(harness).to receive(:tick_failed?).and_return(false)
      allow(harness).to receive(:sleep)

      harness.send(:monitor_resources)
      expect(harness).to have_received(:duration_exceeded?).twice
    end

    it 'breaks cleanly natively completely securely' do
      allow(harness).to receive(:print_table_header)
      allow(harness).to receive_messages(duration_exceeded?: false, tick_failed?: true)

      harness.send(:monitor_resources)
      expect(harness).to have_received(:tick_failed?)
    end
  end

  describe '#duration_exceeded?' do
    it 'returns correctly based on elapsed time' do
      expect(harness.send(:duration_exceeded?)).to be false
      harness.instance_variable_set(:@start_time, Time.now.utc - 10)
      expect(harness.send(:duration_exceeded?)).to be true
    end
  end

  describe '#tick_failed?' do
    it 'handles missing socket securely' do
      allow(harness).to receive_messages(extract_client_stats: [0, '0.0', 1, '1 MB'], missing_socket?: true)
      expect(harness.send(:tick_failed?)).to be true
    end

    it 'checks actively successfully missing processes' do
      allow(harness).to receive_messages(extract_client_stats: [1, '0.0', 1, '1 MB'], missing_socket?: false)
      allow(harness.instance_variable_get(:@pm)).to receive(:missing_process?).and_return(true)
      expect(harness.send(:tick_failed?)).to be true
    end

    it 'prints combined stats predictably' do
      allow(harness).to receive_messages(extract_client_stats: [1, '0.0', 1, '1 MB'], missing_socket?: false)
      allow(harness.instance_variable_get(:@pm)).to receive(:missing_process?).and_return(false)
      allow(harness).to receive(:print_combined_stats)
      expect(harness.send(:tick_failed?)).to be false
    end
  end

  describe '#bump_file_limits' do
    it 'rescues seamlessly fully natively' do
      allow(Process).to receive(:setrlimit).and_raise(Errno::EPERM)
      expect { harness.send(:bump_file_limits) }.not_to raise_error
    end

    it 'executes actively elegantly' do
      allow(Process).to receive(:setrlimit)
      expect { harness.send(:bump_file_limits) }.not_to raise_error
    end
  end

  describe '#missing_socket?' do
    it 'returns functionally reliably robustly smoothly' do
      harness.instance_variable_set(:@peak_connections, 100)
      expect(harness.send(:missing_socket?, 0, '0', 1, 'M')).to be true
    end

    it 'returns elegantly precisely mathematically dynamically' do
      harness.instance_variable_set(:@peak_connections, 100)
      expect(harness.send(:missing_socket?, 1, '0', 1, 'M')).to be false
    end
  end
end
