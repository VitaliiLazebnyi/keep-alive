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

  describe '#initialize' do
    it 'raises ArgumentError on invalid connections' do
      expect { described_class.new(connections: 0) }.to raise_error(ArgumentError, /connections must be >= 1/)
    end

    it 'raises ArgumentError on invalid target duration' do
      expect { described_class.new(connections: 1, target_duration: -1.0) }.to raise_error(ArgumentError, /target_duration must be >= 0.0/)
    end
  end

  describe '#start' do
    context 'with typical parameters' do
      before do
        allow(harness).to receive(:loop).and_yield
        allow(harness).to receive(:sleep)
        harness.start
      end

      it 'sets file limits correctly', :rspec do
        expect(Process).to have_received(:setrlimit).with(Process::RLIMIT_NOFILE, 1026)
      end

      it 'spawns processes successfully twice', :rspec do
        expect(Process).to have_received(:spawn).twice
      end
    end

    context 'with alternate target arguments' do
      it 'logs MULTIPLE TARGETS cleanly' do
        h_multi = described_class.new(connections: 1, target_urls: ['http://t1', 'http://t2'])
        allow(h_multi).to receive(:spawn_processes)
        allow(h_multi).to receive(:monitor_resources)
        expect { h_multi.start }.to output(/MULTIPLE TARGETS/).to_stdout
      end

      it 'logs EXTERNAL URL cleanly' do
        h_ext = described_class.new(connections: 1, target_urls: ['http://t1'])
        allow(h_ext).to receive(:spawn_processes)
        allow(h_ext).to receive(:monitor_resources)
        expect { h_ext.start }.to output(/EXTERNAL URL/).to_stdout
      end

      it 'logs HTTPS cleanly' do
        h_sec = described_class.new(connections: 1, use_https: true)
        allow(h_sec).to receive(:spawn_processes)
        allow(h_sec).to receive(:monitor_resources)
        expect { h_sec.start }.to output(/HTTPS/).to_stdout
      end
    end

    it 'traps INT signal effectively securely' do
      allow(harness).to receive(:spawn_processes)
      allow(harness).to receive(:monitor_resources)
      allow(harness).to receive(:trap).with('INT').and_yield
      allow(harness).to receive(:exit)
      expect { harness.start }.to output(/Caught interrupt/).to_stdout
    end

    it 'gracefully logs if setting file limits permission denied', :rspec do
      allow(Process).to receive(:setrlimit).and_raise(Errno::EPERM)

      # Avoid start from going into monitoring
      allow(harness).to receive(:spawn_processes)
      allow(harness).to receive(:monitor_resources)

      expect { harness.start }.not_to raise_error
    end
  end

  describe 'resource helpers' do
    it 'returns EXTERNAL values when pid is nil', :rspec do
      expect(harness.send(:process_stats, nil)).to eq(['EXTERNAL', 'EXTERNAL', 0.0, 0])
    end

    context 'when on Linux with native /proc stats' do
      let(:proc_stat) { "123 (ruby) S 1 1 1 0 -1 0 0 0 0 0 100 200 0 0 20 0 1 0 12345 12345 10240 1 1 1\n" }
      
      it 'calculates stats successfully bypassing fallback', :rspec do
        allow(File).to receive(:read).with('/proc/123/stat').and_return(proc_stat)
        allow(File).to receive(:read).with('/proc/123/statm').and_return("10240 2560 1 1 1 1 1\n")
        allow(File).to receive(:read).with('/proc/123/status').and_return("Threads:\t4\n")
        
        allow(File).to receive(:exist?).with('/usr/bin/getconf').and_return(true)
        allow(Open3).to receive(:capture2).with('getconf PAGE_SIZE').and_return(['4096', nil])

        stats = harness.send(:process_stats, 123)
        expect(stats[3]).to eq(4)
        
        # Second pass to cover CPU diff block successfully
        time = Time.now
        allow(Time).to receive(:now).and_return(time)
        harness.send(:process_stats, 123)

        allow(Time).to receive(:now).and_return(time + 1.0)
        allow(File).to receive(:read).with('/proc/123/stat').and_return("123 (ruby) S 1 1 1 0 -1 0 0 0 0 0 150 250 0 0 20 0 1 0 12345 12345 10240 1 1 1\n")
        stats_diff = harness.send(:process_stats, 123)
        expect(stats_diff[0]).not_to be_empty
      end

      it 'handles getconf crashes gracefully', :rspec do
        allow(File).to receive(:read).with('/proc/123/stat').and_return(proc_stat)
        allow(File).to receive(:read).with('/proc/123/statm').and_return("10240 2560 1 1 1 1 1\n")
        allow(File).to receive(:read).with('/proc/123/status').and_return("Threads:\t4\n")
        allow(File).to receive(:exist?).with('/usr/bin/getconf').and_return(true)
        allow(Open3).to receive(:capture2).with('getconf PAGE_SIZE').and_raise(StandardError)
        expect { harness.send(:process_stats, 123) }.not_to raise_error
      end
    end

    context 'when PS command succeeds' do
      let(:stats) do
        allow(File).to receive(:read).with('/proc/123/stat').and_raise(Errno::ENOENT)
        allow(Open3).to receive(:capture2).with('ps', '-o', '%cpu,rss', '-p', '123').and_return(["%CPU   RSS\n  5.5 10240\n", nil])
        allow(Open3).to receive(:capture2).with('ps -M -p 123').and_return(["PID  TT  STAT      TIME COMMAND\n123  ??  S      0:00.01 ruby\n123  ??  S      0:00.01 ruby\n", nil])
        harness.send(:process_stats, 123)
      end

      it 'returns exact mocked percentages', :rspec do
        expect(stats[0]).to eq('5.5')
      end

      it 'returns correct mocked memory string', :rspec do
        expect(stats[1]).to eq('10.0 MB')
      end

      it 'returns correct mapped kilobyte values', :rspec do
        expect(stats[2]).to eq(10_240.0)
      end
    end

    it 'returns N/A if PS fails', :rspec do
      allow(Open3).to receive(:capture2).and_raise(StandardError)
      expect(harness.send(:process_stats, 123)).to eq(['N/A', 'N/A', 0.0, 0])
    end

    it 'counts logically established connections via lsof', :rspec do
      mock_lsof = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nruby 123 u 4u IPv4 0t0 TCP *:8080 (ESTABLISHED)\n"
      allow(Open3).to receive(:capture2).with('lsof -p 123 -n -P').and_return([mock_lsof, nil])

      expect(harness.send(:count_established_connections, 123)).to eq(1)
    end

    it 'handles check_bottlenecks string parsing elegantly', :rspec do
      log_dir = File.expand_path('../../logs', __dir__)
      allow(File).to receive(:read).with(File.join(log_dir, 'client.log')).and_return('ERROR_EMFILE ERROR_THREADLIMIT')
      allow(File).to receive(:read).with(File.join(log_dir, 'client.err')).and_return('ERROR_EADDRNOTAVAIL')
      allow($stdout).to receive(:puts)
      expect { harness.send(:check_bottlenecks) }.not_to raise_error
    end

    it 'gracefully logs when client process has terminated', :rspec do
      allow(harness).to receive(:loop).and_yield
      harness.instance_variable_set(:@client_pid, 5678)
      allow(Process).to receive(:getpgid).with(5678).and_raise(Errno::ESRCH)
      expect { harness.send(:monitor_resources) }.to output(/Client process has terminated/).to_stdout
    end

    context 'when server process has terminated' do
      before do
        allow(harness).to receive(:loop).and_yield
        harness.instance_variable_set(:@client_pid, 5678)
        harness.instance_variable_set(:@server_pid, 1234)
        allow(Process).to receive(:getpgid).with(5678).and_return(true)
        allow(Process).to receive(:getpgid).with(1234).and_raise(Errno::ESRCH)
      end

      it 'gracefully logs output', :rspec do
        expect { harness.send(:monitor_resources) }.to output(/Server process has terminated/).to_stdout
      end
    end
  end

  describe '#export_telemetry' do
    context 'when JSON explicitly set' do
      let(:harness_export) { described_class.new(connections: 2, export_json: 'test_telemetry.json') }
      let(:exported_json) do
        json_output = nil
        allow(File).to receive(:write).with('test_telemetry.json', instance_of(String)) { |_, string| json_output = string }
        allow($stdout).to receive(:puts)
        harness_export.send(:export_telemetry)
        JSON.parse(json_output.to_s)
      end

      before do
        log_dir = File.expand_path('../../logs', __dir__)
        allow(File).to receive(:read).with(File.join(log_dir, 'client.log')).and_return('ERROR_EMFILE ERROR_THREADLIMIT')
        allow(File).to receive(:read).with(File.join(log_dir, 'client.err')).and_return('ERROR_EADDRNOTAVAIL')
        harness_export.instance_variable_set(:@peak_connections, 100)
      end

      it 'exports peak_connections correctly', :rspec do
        expect(exported_json['peak_connections']).to eq(100)
      end

      it 'counts thread_limit correctly', :rspec do
        expect(exported_json['errors']['thread_limit']).to eq(1)
      end

      it 'counts emfile correctly', :rspec do
        expect(exported_json['errors']['emfile']).to eq(1)
      end

      it 'counts eaddrnotavail correctly', :rspec do
        expect(exported_json['errors']['eaddrnotavail']).to eq(1)
      end

      it 'logs the syncing specifically', :rspec do
        allow(File).to receive(:write)
        expect { harness_export.send(:export_telemetry) }.to output(/Telemetry JSON securely sinked/).to_stdout
      end
    end

    context 'when telemetry export is not explicitly set' do
      before do
        allow(File).to receive(:write)
      end

      it 'does not ignore exports silently', :rspec do
        allow($stdout).to receive(:puts)
        harness.send(:export_telemetry)
        expect(File).not_to have_received(:write)
      end

      it 'does not show logs for sinking', :rspec do
        expect { harness.send(:export_telemetry) }.not_to output(/Telemetry JSON securely sinked/).to_stdout
      end
    end
  end

  describe '#spawn_processes boost' do
    let(:harness_retry) { described_class.new(connections: 1) }

    before do
      allow(Process).to receive(:spawn).and_return(123)
      allow(harness_retry).to receive(:sleep)

      call_count = 0
      allow(Socket).to receive(:tcp) do
        call_count += 1
        call_count == 1 ? raise(Errno::ECONNREFUSED) : instance_double(TCPSocket, close: true)
      end
    end

    it 'sleeps and retries specifically on ECONNREFUSED', :rspec do
      harness_retry.send(:spawn_processes)
      expect(harness_retry).to have_received(:sleep).once
    end
  end
end
