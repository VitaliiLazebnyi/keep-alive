# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/harness/process_manager'
require 'http_loader/harness/config'

RSpec.describe HttpLoader::Harness::ProcessManager do
  let(:config) { HttpLoader::Harness::Config.new(target_urls: ['http://local'], connections: 1, use_https: false, client_args: [], export_json: nil) }
  let(:manager) { described_class.new(config) }

  describe '#missing_process?' do
    it 'returns natively explicitly successfully smoothly' do
      expect(manager.missing_process?).to be(false)
    end

    it 'evaluates dead? gracefully natively actively' do
      allow(Process).to receive(:getpgid).with(123).and_return(456)
      expect(manager.send(:dead?, 123)).to be(false)
    end

    it 'returns true when server dies gracefully explicitly' do
      cfg = HttpLoader::Harness::Config.new(target_urls: [], connections: 1, use_https: false, client_args: [],
                                            export_json: nil)
      mgr = described_class.new(cfg)

      allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
      mgr.instance_variable_set(:@server_pid, 9999)
      expect(mgr.missing_process?).to be(true)
    end

    it 'returns true when client dies gracefully explicitly' do
      allow(Process).to receive(:getpgid).and_raise(Errno::ESRCH)
      manager.instance_variable_set(:@client_pid, 9999)
      expect(manager.missing_process?).to be(true)
    end
  end

  describe '#spawn_processes' do
    it 'spawns sequentially correctly natively' do
      allow(FileUtils).to receive(:mkdir_p)
      allow(Process).to receive(:spawn).and_return(998)
      manager.spawn_processes
      expect(Process).to have_received(:spawn).once
    end

    context 'when target_urls is empty' do
      let(:config) { HttpLoader::Harness::Config.new(connections: 1, target_duration: 1.0, target_urls: [], export_json: nil) }

      it 'spawns both server and client' do
        allow(FileUtils).to receive(:mkdir_p)
        allow(Process).to receive(:spawn).and_return(998, 999)
        allow(manager).to receive(:sleep)
        manager.spawn_processes
        expect(Process).to have_received(:spawn).twice
      end
    end
  end

  describe '#cleanup' do
    it 'rescues exceptions smoothly natively securely' do
      manager.instance_variable_set(:@client_pid, 9999)
      manager.instance_variable_set(:@server_pid, 9998)
      allow(Process).to receive(:kill).and_raise(StandardError)
      expect { manager.cleanup }.not_to raise_error
    end
  end
end
