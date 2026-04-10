# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe KeepAlive::Harness do
  let(:harness) { described_class.new(connections: 2) }

  before do
    allow($stdout).to receive(:puts)
    allow(Process).to receive(:setrlimit)
    allow(Process).to receive(:spawn).and_return(1234, 5678)
    allow(Process).to receive(:kill)
    allow(Process).to receive(:getpgid).and_return(true)
    allow(Kernel).to receive(:sleep)
  end

  describe '#start' do
    it 'sets file limits, spawns processes and handles interrupts', rspec: true do
      expect(Process).to receive(:setrlimit).with(Process::RLIMIT_NOFILE, 1026)
      expect(Process).to receive(:spawn).twice

      # Stop the infinite monitoring loop dynamically
      allow(harness).to receive(:loop).and_yield
      allow(harness).to receive(:sleep)

      harness.start
    end

    it 'gracefully logs if setting file limits permission denied', rspec: true do
      allow(Process).to receive(:setrlimit).and_raise(Errno::EPERM)

      # Avoid start from going into monitoring
      allow(harness).to receive(:spawn_processes)
      allow(harness).to receive(:monitor_resources)

      expect { harness.start }.not_to raise_error
    end
  end

  describe 'resource helpers' do
    it 'returns EXTERNAL values when pid is nil', rspec: true do
      expect(harness.send(:process_stats, nil)).to eq(['EXTERNAL', 'EXTERNAL', 0.0])
    end

    it 'returns exact mocked percentages when PS command succeeds', rspec: true do
      allow(File).to receive(:read).with('/proc/123/stat').and_raise(Errno::ENOENT)
      allow(Open3).to receive(:capture2).with('ps', '-o', '%cpu,rss', '-p', '123').and_return(["%CPU   RSS\n  5.5 10240\n", nil])

      cpu, mem_str, kb = harness.send(:process_stats, 123)
      expect(cpu).to eq('5.5')
      expect(mem_str).to eq('10.0 MB')
      expect(kb).to eq(10_240.0)
    end

    it 'returns N/A if PS fails', rspec: true do
      allow(Open3).to receive(:capture2).and_raise(StandardError)
      expect(harness.send(:process_stats, 123)).to eq(['N/A', 'N/A', 0.0])
    end

    it 'counts logically established connections via lsof', rspec: true do
      mock_lsof = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nruby 123 u 4u IPv4 0t0 TCP *:8080 (ESTABLISHED)\n"
      allow(Open3).to receive(:capture2).with('lsof -p 123 -n -P').and_return([mock_lsof, nil])

      expect(harness.send(:count_established_connections, 123)).to eq(1)
    end

    it 'handles check_bottlenecks string parsing elegantly', rspec: true do
      allow(File).to receive(:read).with('client.log').and_return('ERROR_EMFILE ERROR_THREADLIMIT')
      allow(File).to receive(:read).with('client.err').and_return('ERROR_EADDRNOTAVAIL')
      allow($stdout).to receive(:puts)
      expect { harness.send(:check_bottlenecks) }.not_to raise_error
    end
    it 'gracefully logs when client process has terminated', rspec: true do
      allow(harness).to receive(:loop).and_yield
      harness.instance_variable_set(:@client_pid, 5678)
      allow(Process).to receive(:getpgid).with(5678).and_raise(Errno::ESRCH)
      expect { harness.send(:monitor_resources) }.to output(/Client process has terminated/).to_stdout
    end

    it 'gracefully logs when server process has terminated', rspec: true do
      allow(harness).to receive(:loop).and_yield
      harness.instance_variable_set(:@client_pid, 5678)
      harness.instance_variable_set(:@server_pid, 1234)
      allow(Process).to receive(:getpgid).with(5678).and_return(true)
      allow(Process).to receive(:getpgid).with(1234).and_raise(Errno::ESRCH)

      expect { harness.send(:monitor_resources) }.to output(/Server process has terminated/).to_stdout
    end

    describe '#export_telemetry' do
      let(:harness_with_export) { described_class.new(connections: 2, export_json: 'test_telemetry.json') }

      it 'exports telemetry to json file when explicitly set', rspec: true do
        allow(File).to receive(:read).with('client.log').and_return('ERROR_EMFILE ERROR_THREADLIMIT')
        allow(File).to receive(:read).with('client.err').and_return('ERROR_EADDRNOTAVAIL')
        harness_with_export.instance_variable_set(:@peak_connections, 100)

        expect(File).to receive(:write).with('test_telemetry.json', instance_of(String)) do |_, json_string|
          data = JSON.parse(json_string)
          expect(data['peak_connections']).to eq(100)
          expect(data['errors']['emfile']).to eq(1)
          expect(data['errors']['eaddrnotavail']).to eq(1)
          expect(data['errors']['thread_limit']).to eq(1)
        end
        expect { harness_with_export.send(:export_telemetry) }.to output(/Telemetry JSON securely sinked/).to_stdout
      end

      it 'ignores telemetry export if not explicitly set', rspec: true do
        expect(File).not_to receive(:write)
        expect { harness.send(:export_telemetry) }.not_to output(/Telemetry JSON securely sinked/).to_stdout
      end
    end
  end
end
