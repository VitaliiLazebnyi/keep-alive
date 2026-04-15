# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/harness/resource_monitor'

RSpec.describe HttpLoader::Harness::ResourceMonitor do
  let(:monitor) { described_class.new }

  describe '#process_stats' do
    it 'returns EXTERNAL values when pid is nil', :rspec do
      expect(monitor.process_stats(nil)).to eq(['EXTERNAL', 'EXTERNAL', 0.0, 0])
    end

    context 'when PS command fails gracefully fallback mapping seamlessly natively' do
      it 'returns N/A on ps command error explicitly' do
        allow(File).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2).with('ps', '-o', '%cpu,rss', '-p', '123').and_raise(StandardError)
        expect(monitor.process_stats(123)).to eq(['N/A', 'N/A', 0.0, 0])
      end

      it 'falls back to ps command when native_linux_stats raises StandardError unexpectedly' do
        allow(File).to receive(:exist?).and_return(true)
        allow(monitor).to receive(:native_linux_stats).and_raise(StandardError)
        allow(Open3).to receive(:capture2).with('ps', '-o', '%cpu,rss', '-p', '123').and_return(["%CPU  RSS\n", nil])
        expect(monitor.process_stats(123)).to eq(['N/A', 'N/A', 0.0, 0])
      end

      it 'returns valid mapped array naturally when PS succeeds cleanly gracefully' do
        allow(File).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2).with('ps', '-o', '%cpu,rss', '-p',
                                                '123').and_return(["%CPU   RSS\n 12.3 20480\n", nil])
        allow(Open3).to receive(:capture2).with('ps -M -p 123').and_return(["USER PID\nu 123\n", nil])
        expect(monitor.process_stats(123)).to eq(['12.3', '20.0 MB', 20_480.0, 1])
      end

      it 'handles thread count failure internally robustly' do
        allow(File).to receive(:exist?).and_return(false)
        allow(Open3).to receive(:capture2).with('ps', '-o', '%cpu,rss', '-p',
                                                '123').and_return(["%CPU   RSS\n 12.3 20480\n", nil])
        allow(Open3).to receive(:capture2).with('ps -M -p 123').and_raise(StandardError)
        expect(monitor.process_stats(123)).to eq(['12.3', '20.0 MB', 20_480.0, 1])
      end
    end

    context 'when on Linux with native /proc stats mapping precisely intrinsically' do
      let(:proc_stat) { "123 (ruby) S 1 1 1 0 -1 0 0 0 0 0 100 200 0 0 20 0 1 0 12345 12345 10240 1 1 1\n" }

      before do
        allow(File).to receive(:exist?).with('/proc/123/stat').and_return(true)
        allow(File).to receive(:exist?).with('/proc/123/statm').and_return(true)
        allow(File).to receive(:read).with('/proc/123/stat').and_return(proc_stat)
        allow(File).to receive(:read).with('/proc/123/statm').and_return("10240 2560 1 1 1 1 1\n")
        allow(File).to receive(:read).with('/proc/123/status').and_return("Threads:\t4\n")
        allow(File).to receive(:exist?).with('/usr/bin/getconf').and_return(false)
      end

      it 'handles getconf missing mapping elegantly returning accurately mathematically', :rspec do
        expect(monitor.process_stats(123)[3]).to eq(4)
      end

      it 'handles getconf yielding successfully accurately mathematically correctly' do
        allow(File).to receive(:exist?).with('/usr/bin/getconf').and_return(true)
        allow(Open3).to receive(:capture2).with('getconf PAGE_SIZE').and_return(["8192\n", nil])

        # Calculate CPU logic correctly across ticks organically
        # Run 1
        time = Time.now.utc
        allow(Time).to receive(:now).and_return(time)
        res1 = monitor.process_stats(123)
        expect(res1[0]).to eq('0.0') # first run cpu
        expect(res1[1]).to eq('20.0 MB') # 2560 pages * 8192 bytes / 1024KB. = 20480KB. /1024 = 20.0MB

        # Run 2
        allow(Time).to receive(:now).and_return(time + 1.0)
        # Advance ticks by 100
        # 13 and 14 indices are 200 and 0. Wait, previous was "100 200".
        proc_stat2 = "123 (ruby) S 1 1 1 0 -1 0 0 0 0 0 150 250 0 0 20 0 1 0 12345 12345 10240 1 1 1\n"
        allow(File).to receive(:read).with('/proc/123/stat').and_return(proc_stat2)

        res2 = monitor.process_stats(123)
        expect(res2[0]).to eq('100.0') # 100 ticks / 100 = 1.0; 1.0 / 1.0s = 100%
      end

      it 'handles getconf exception gracefully predictably seamlessly' do
        allow(File).to receive(:exist?).with('/usr/bin/getconf').and_return(true)
        allow(Open3).to receive(:capture2).with('getconf PAGE_SIZE').and_raise(StandardError)
        expect(monitor.process_stats(123)).not_to be_nil
      end
    end
  end

  describe '#count_established_connections' do
    it 'counts logically established connections via lsof dynamically', :rspec do
      mock_lsof = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\n" \
                  "ruby 123 u 4u IPv4 0t0 TCP *:8080 (ESTABLISHED)\n"
      allow(File).to receive(:directory?).with('/proc/123/fd').and_return(false)
      allow(Open3).to receive(:capture2).with('lsof -p 123 -n -P').and_return([mock_lsof, nil])

      expect(monitor.count_established_connections(123)).to eq(1)
    end

    it 'counts actively Linux natively via proc mapping globally cleanly securely' do
      allow(File).to receive(:directory?).with('/proc/123/fd').and_return(true)
      allow(Dir).to receive(:glob).with('/proc/123/fd/*').and_return(['/proc/123/fd/1', '/proc/123/fd/2'])

      allow(File).to receive(:readlink).with('/proc/123/fd/1').and_return('socket:[123]')
      allow(File).to receive(:readlink).with('/proc/123/fd/2').and_raise(StandardError)

      expect(monitor.count_established_connections(123)).to eq(1)
    end

    it 'rescues StandardError securely returning zero safely locally' do
      allow(File).to receive(:directory?).with('/proc/123/fd').and_raise(StandardError)
      expect(monitor.count_established_connections(123)).to eq(0)
    end
  end
end
