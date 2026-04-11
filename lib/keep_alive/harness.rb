# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'open3'
require 'json'
require 'fileutils'

module KeepAlive
  class Harness
    extend T::Sig

    sig do
      params(
        connections: Integer, target_urls: T::Array[String], use_https: T::Boolean, client_args: T::Array[String],
        export_json: T.nilable(String), target_duration: Float
      ).void
    end
    def initialize( # rubocop:disable Metrics/ParameterLists
      connections:, target_urls: [], use_https: false, client_args: [],
      export_json: nil, target_duration: 0.0
    )
      raise ArgumentError, 'connections must be >= 1' if connections < 1
      raise ArgumentError, 'target_duration must be >= 0.0' if target_duration.negative?

      @connections = connections
      @target_urls = target_urls
      @use_https = use_https
      @client_args = client_args
      @server_pid = T.let(nil, T.nilable(Integer))
      @client_pid = T.let(nil, T.nilable(Integer))
      @start_time = T.let(Time.now.utc, Time)
      @peak_connections = T.let(0, Integer)
      @export_json = export_json
      @target_duration = target_duration
      @log_dir = T.let(File.expand_path('../../logs', __dir__), String)
      @cpu_prev = T.let({}, T::Hash[Integer, T::Hash[Symbol, T.untyped]])
    end

    sig { void }
    def start
      $stdout.sync = true

      if @target_urls.size > 1
        puts "[Harness] Starting test with #{@connections} connections to **MULTIPLE TARGETS** (#{@target_urls.size} URLs)."
      elsif @target_urls.size == 1
        puts "[Harness] Starting test with #{@connections} connections to **EXTERNAL URL** #{@target_urls.first}."
      elsif @use_https
        puts "[Harness] Starting test with #{@connections} connections over **HTTPS**."
      else
        puts "[Harness] Starting test with #{@connections} connections over **HTTP**."
      end

      bump_file_limits
      spawn_processes

      trap('INT') do
        puts "\n[Harness] Caught interrupt, cleaning up processes..."
        cleanup
        exit(0)
      end

      monitor_resources
    ensure
      export_telemetry
      cleanup
    end

    private

    sig { void }
    def bump_file_limits
      Process.setrlimit(Process::RLIMIT_NOFILE, @connections + 1024)
    rescue Errno::EPERM
      puts '[Harness] Warning: Could not set RLIMIT_NOFILE automatically.'
      puts '          Suggested to run `ulimit -n 4096` manually before running this test.'
    end

    sig { void }
    def spawn_processes
      FileUtils.mkdir_p(@log_dir)

      unless @target_urls.any?
        server_cmd = 'ruby bin/server'
        server_cmd += ' --https' if @use_https
        @server_pid = Process.spawn(server_cmd, out: File.join(@log_dir, 'server.log'), err: File.join(@log_dir, 'server.err'))
        puts "[Harness] Started server with PID #{@server_pid}"
        puts '[Harness] Waiting for server to initialize...'
        sleep(2)
      end

      client_args_str = @client_args.empty? ? "--connections_count=#{@connections}" : @client_args.join(' ')
      client_cmd = "ruby bin/client #{client_args_str}"

      @client_pid = Process.spawn(client_cmd, out: File.join(@log_dir, 'client.log'), err: File.join(@log_dir, 'client.err'))
      puts "[Harness] Started client with PID #{@client_pid} (Command: #{client_cmd})"
    end

    sig { void }
    def cleanup
      begin
        Process.kill('INT', T.must(@server_pid)) if @server_pid
      rescue StandardError; nil
      end
      begin
        Process.kill('INT', T.must(@client_pid)) if @client_pid
      rescue StandardError; nil
      end
    end

    sig { params(pid: T.nilable(Integer)).returns([String, String, Float, Integer]) }
    def process_stats(pid)
      return ['EXTERNAL', 'EXTERNAL', 0.0, 0] if pid.nil?

      begin
        proc_stat = File.read("/proc/#{pid}/stat").split
        proc_statm = File.read("/proc/#{pid}/statm").split
        status_data = File.read("/proc/#{pid}/status")
        threads = status_data.match(/Threads:\s+(\d+)/)&.[](1)&.to_i || 1

        rss_pages = T.must(proc_statm[1]).to_i
        page_size = 4096 # standard hardcode fallback
        if File.exist?('/usr/bin/getconf')
          begin
            out, _s = Open3.capture2('getconf PAGE_SIZE')
            page_size = out.to_i if out.to_i.positive?
          rescue StandardError
            nil
          end
        end

        rss_kb = (rss_pages * page_size) / 1024.0
        rss_mb = (rss_kb / 1024.0).round(2)

        utime = T.must(proc_stat[13]).to_f
        stime = T.must(proc_stat[14]).to_f
        total_ticks = utime + stime

        prev = @cpu_prev[pid]
        now = Time.now.utc

        cpu_perc = 0.0
        if prev
          time_diff = now - prev[:time]
          tick_diff = total_ticks - prev[:ticks]
          hz = 100.0
          cpu_perc = ((tick_diff / hz) / time_diff * 100).round(1) if time_diff.positive?
        end

        @cpu_prev[pid] = { ticks: total_ticks, time: now }

        [cpu_perc.to_s, "#{rss_mb} MB", rss_kb, threads]
      rescue StandardError
        # Fallback to direct Ruby API logic when /proc isn't native (e.g. macOS)
        begin
          out, _s = Open3.capture2('ps', '-o', '%cpu,rss', '-p', pid.to_s)
          lines = out.strip.split("\n")
          return ['N/A', 'N/A', 0.0, 0] if lines.size < 2

          cpu, rss_kb_str = T.must(lines[1]).strip.split(/\s+/)
          rss_kb_val = T.must(rss_kb_str).to_f
          rss_mb_val = (rss_kb_val / 1024.0).round(2)

          threads = begin
            out2, _s = Open3.capture2("ps -M -p #{pid}")
            [out2.strip.split("\n").size - 1, 0].max
          rescue StandardError; 1
          end

          [T.must(cpu), "#{rss_mb_val} MB", rss_kb_val, threads]
        rescue StandardError
          ['N/A', 'N/A', 0.0, 0]
        end
      end
    end

    sig { params(pid: T.nilable(Integer)).returns(Integer) }
    def count_established_connections(pid)
      return 0 if pid.nil?

      if File.directory?("/proc/#{pid}/fd")
        Dir.entries("/proc/#{pid}/fd").count do |fd|
          next false if ['.', '..'].include?(fd)

          begin
            File.readlink("/proc/#{pid}/fd/#{fd}").start_with?('socket:[')
          rescue StandardError
            false
          end
        end
      else
        out, _s = Open3.capture2("lsof -p #{pid} -n -P")
        out.scan('ESTABLISHED').count
      end
    rescue StandardError
      0
    end

    sig { void }
    def monitor_resources
      puts '[Harness] Monitoring resources (Press Ctrl+C to stop)...'
      header_format = '%-10s | %-11s | %-16s | %-14s | %-14s | %-16s | %-14s | %-14s'
      row_format    = '%-10s | %-11s | %-16s | %-14s | %-14s | %-16s | %-14s | %-14s'

      puts '-' * 125
      puts format(header_format, 'Time (UTC)', 'Real Conns', 'Srv CPU/Thrds', 'Server Mem', 'Srv Mem/Conn',
                  'Cli CPU/Thrds', 'Client Mem', 'Cli Mem/Conn')
      puts '-' * 125

      @start_time = Time.now.utc

      loop do
        elapsed = Time.now.utc - @start_time
        if @target_duration.positive? && elapsed >= @target_duration
          puts "[Harness] Target duration mathematically reached (#{@target_duration}s). Triggering auto-shutdown."
          break
        end

        time = Time.now.utc.strftime('%H:%M:%S')
        server_cpu, server_mem, server_kb, server_threads = process_stats(@server_pid)
        client_cpu, client_mem, client_kb, client_threads = process_stats(@client_pid)

        srv_cpu_info = @server_pid ? "#{server_cpu}% / #{server_threads}T" : 'EXTERNAL'
        cli_cpu_info = "#{client_cpu}% / #{client_threads}T"

        active_client = count_established_connections(@client_pid)
        active_server = count_established_connections(@server_pid)

        @peak_connections = [@peak_connections, active_client].max

        if @target_urls.any? && @peak_connections.positive? && active_client.zero?
          elapsed = Time.now.utc - @start_time
          puts format(row_format, time, active_client, srv_cpu_info, server_mem, 'N/A',
                      cli_cpu_info, client_mem, 'N/A')
          puts "\n[Harness] \u26A0\uFE0F EXTERNAL SERVER DISCONNECTED! All TCP Keep-Alive sockets were forcefully dropped."
          puts "[Harness] The endpoints natively survived for mathematically #{elapsed.round(2)} seconds."
          break
        end

        srv_mem_conn = if @server_pid && server_kb.positive? && active_server.positive?
                         "#{(server_kb / active_server.to_f).round(2)} KB"
                       elsif @server_pid.nil?
                         'EXTERNAL'
                       else
                         'N/A'
                       end

        cli_mem_conn = if client_kb.positive? && active_client.positive?
                         "#{(client_kb / active_client.to_f).round(2)} KB"
                       else
                         'N/A'
                       end

        begin
          Process.getpgid(T.must(@client_pid)) if @client_pid
        rescue Errno::ESRCH
          puts '[Harness] Client process has terminated.'
          break
        end

        if @server_pid
          begin
            Process.getpgid(T.must(@server_pid))
          rescue Errno::ESRCH
            puts '[Harness] Server process has terminated.'
            break
          end
        end

        puts format(row_format, time, active_client, srv_cpu_info, server_mem, srv_mem_conn,
                    cli_cpu_info, client_mem, cli_mem_conn)

        check_bottlenecks
        sleep(2)
      end
    end

    sig { void }
    def export_telemetry
      return unless @export_json

      full_log = begin
        File.read(File.join(@log_dir, 'client.log'))
      rescue StandardError; ''
      end + begin
        File.read(File.join(@log_dir, 'client.err'))
      rescue StandardError; ''
      end

      emfile_count  = full_log.scan('ERROR_EMFILE').size
      eaddr_count   = full_log.scan('ERROR_EADDRNOTAVAIL').size
      thread_errors = full_log.scan('ERROR_THREADLIMIT').size

      payload = {
        peak_connections: @peak_connections,
        test_duration_seconds: (Time.now.utc - @start_time).round(2),
        errors: {
          emfile: emfile_count,
          eaddrnotavail: eaddr_count,
          thread_limit: thread_errors
        }
      }

      File.write(@export_json, JSON.generate(payload))
      puts "[Harness] Telemetry JSON securely sinked to #{@export_json}."
    end

    sig { void }
    def check_bottlenecks
      full_log = begin
        File.read(File.join(@log_dir, 'client.log'))
      rescue StandardError; ''
      end + begin
        File.read(File.join(@log_dir, 'client.err'))
      rescue StandardError; ''
      end

      emfile_count  = full_log.scan('ERROR_EMFILE').size
      eaddr_count   = full_log.scan('ERROR_EADDRNOTAVAIL').size
      thread_errors = full_log.scan('ERROR_THREADLIMIT').size

      errors = []
      errors << "[OS FDs Limit: #{emfile_count} EMFILE]" if emfile_count.positive?
      errors << "[OS Ports Limit: #{eaddr_count} EADDRNOTAVAIL]" if eaddr_count.positive?
      errors << "[OS Thread Limit: #{thread_errors} ThreadError]" if thread_errors.positive?

      puts format('   => BOTTLENECK ACTIVE: %s', errors.join(' | ')) if errors.any?
    rescue StandardError
      nil
    end
  end
end
