# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'net/http'
require 'uri'
require 'openssl'
require 'socket'
require 'async'
require 'async/semaphore'
require 'time'
require 'fileutils'
module KeepAlive
  class Client
    extend T::Sig

    sig do
      params(
        connections: Integer,
        target_urls: T::Array[String],
        use_https: T::Boolean,
        verbose: T::Boolean,
        ping: T::Boolean,
        ping_period: Integer,
        keep_alive_timeout: Float,
        connections_per_second: Integer,
        max_concurrent_connections: Integer,
        reopen_closed_connections: T::Boolean,
        reopen_interval: Float,
        read_timeout: Float,
        user_agent: String,
        jitter: Float,
        track_status_codes: T::Boolean,
        ramp_up: Float,
        bind_ips: T::Array[String],
        proxy_pool: T::Array[String],
        qps_per_connection: Integer,
        headers: T::Hash[String, String],
        slowloris_delay: Float
      ).void
    end
    def initialize( # rubocop:disable Metrics/ParameterLists
      connections:, target_urls: [], use_https: false,
      verbose: false, ping: true, ping_period: 5,
      keep_alive_timeout: 0.0, connections_per_second: 0,
      max_concurrent_connections: 1000, reopen_closed_connections: false,
      reopen_interval: 1.0, read_timeout: 0.0, user_agent: 'Keep-Alive Test',
      jitter: 0.0, track_status_codes: false,
      ramp_up: 0.0, bind_ips: [], proxy_pool: [],
      qps_per_connection: 0, headers: {},
      slowloris_delay: 0.0
    )
      raise ArgumentError, 'connections must be >= 1' if connections < 1
      raise ArgumentError, 'ping_period must be >= 0' if ping_period.negative?
      raise ArgumentError, 'keep_alive_timeout must be >= 0.0' if keep_alive_timeout.negative?
      raise ArgumentError, 'connections_per_second must be >= 0' if connections_per_second.negative?
      raise ArgumentError, 'max_concurrent_connections must be >= 1' if max_concurrent_connections < 1
      raise ArgumentError, 'reopen_interval must be >= 0.0' if reopen_interval.negative?
      raise ArgumentError, 'read_timeout must be >= 0.0' if read_timeout.negative?
      raise ArgumentError, 'jitter must be >= 0.0' if jitter.negative?
      raise ArgumentError, 'ramp_up must be >= 0.0' if ramp_up.negative?
      raise ArgumentError, 'qps_per_connection must be >= 0' if qps_per_connection.negative?
      raise ArgumentError, 'slowloris_delay must be >= 0.0' if slowloris_delay.negative?

      @connections = connections
      @target_urls = target_urls
      @use_https = use_https
      @verbose = verbose
      @ping = ping
      @ping_period = ping_period
      @keep_alive_timeout = keep_alive_timeout
      @connections_per_second = connections_per_second
      @max_concurrent_connections = max_concurrent_connections
      @reopen_closed_connections = reopen_closed_connections
      @reopen_interval = reopen_interval
      @read_timeout = read_timeout
      @user_agent = user_agent
      @jitter = jitter
      @track_status_codes = track_status_codes
      @ramp_up = ramp_up
      @bind_ips = bind_ips
      @proxy_pool = proxy_pool
      @qps_per_connection = qps_per_connection
      @headers = headers
      @slowloris_delay = slowloris_delay
      @log_dir = T.let(File.expand_path('../../logs', __dir__), String)

      @target_contexts = T.let(build_target_contexts, T::Array[T::Hash[Symbol, T.untyped]])
      @protocol_label = T.let(determine_protocol_label, String)

      @log_queue = T.let(Queue.new, Queue)
      @logger_thread = T.let(spawn_logger_thread, Thread)
    end

    sig { void }
    def start
      label_target = @target_urls.size > 1 ? "#{@target_urls.size} TARGETS" : T.must(@target_contexts.first)[:uri].to_s
      puts "[Client] Starting #{@connections} #{@protocol_label} connections to #{label_target}..."
      puts '[Client] Note: Output of individual pings is suppressed to avoid console spam.' unless @verbose

      trap('INT') { exit(0) }

      # Create/truncate log files deterministically
      FileUtils.mkdir_p(@log_dir)
      File.write(File.join(@log_dir, 'client.err'), '')
      File.write(File.join(@log_dir, 'client.log'), '') if @verbose

      Async do |task|
        semaphore = Async::Semaphore.new(@max_concurrent_connections, parent: task)
        @connections.times do |i|
          delay = if @ramp_up.positive?
                    @ramp_up.to_f / @connections
                  elsif @connections_per_second.positive?
                    1.0 / @connections_per_second
                  else
                    0.0
                  end
          task.sleep(calculate_sleep(delay)) if delay.positive?
          semaphore.async do
            execute_connection(i)
          end
        end
      end
    ensure
      @log_queue << :terminate
      @logger_thread.join
    end

    private

    sig { returns(Thread) }
    def spawn_logger_thread
      Thread.new do # rubocop:disable ThreadSafety/NewThread
        File.open(File.join(@log_dir, 'client.log'), 'a') do |log|
          File.open(File.join(@log_dir, 'client.err'), 'a') do |err|
            loop do
              msg = @log_queue.pop
              break if msg == :terminate

              target, content = msg
              if target == :info
                log.puts content
                log.flush
              elsif target == :error
                err.puts content
                err.flush
              end
            end
          end
        end
      end
    end

    sig { params(base_seconds: Float).returns(Float) }
    def calculate_sleep(base_seconds)
      return base_seconds if @jitter.zero?

      variance = base_seconds * @jitter
      [0.0, base_seconds + rand(-variance..variance)].max
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def build_target_contexts
      urls = @target_urls.any? ? @target_urls : [nil]
      urls.map do |url|
        uri = if url
                URI(url.to_s)
              elsif @use_https
                URI('https://localhost:8443')
              else
                URI('http://localhost:8080')
              end

        args = { read_timeout: @read_timeout.positive? ? @read_timeout : nil }

        begin
          ip_info = Addrinfo.getaddrinfo(T.must(uri.host), uri.port, nil, :STREAM)
          ip = (ip_info.find(&:ipv4?) || ip_info.first)&.ip_address
          args[:ipaddr] = ip if ip
        rescue SocketError => _e
          nil # Fallback to Net::HTTP implicit DNS resolve on crash natively
        end

        http_args = if uri.scheme == 'https'
                      args.merge(use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE)
                    else
                      args
                    end
        { uri: uri, http_args: http_args }
      end
    end

    sig { returns(String) }
    def determine_protocol_label
      if @target_urls.size > 1
        "MULTIPLE TARGETS (#{@target_urls.size})"
      elsif @target_urls.size == 1
        "EXTERNAL #{T.cast(T.must(@target_contexts.first)[:uri], URI::Generic).scheme&.upcase}"
      elsif @use_https
        'HTTPS'
      else
        'HTTP'
      end
    end

    sig { params(client_index: Integer).void }
    def execute_connection(client_index)
      start_time = Time.now

      loop do
        run_http_session(client_index, start_time)
        break unless @reopen_closed_connections

        # If we broke out and need to reopen, we sleep first
        sleep(calculate_sleep(@reopen_interval))
      end
    end

    sig { params(client_index: Integer, start_time: Time).void }
    def run_http_session(client_index, start_time)
      ctx = T.must(@target_contexts[client_index % @target_contexts.size])
      uri = T.cast(ctx[:uri], URI::Generic)
      http_args = T.cast(ctx[:http_args], T::Hash[Symbol, T.untyped])

      http_opts = build_http_opts(client_index, http_args)

      Net::HTTP.start(T.must(uri.host), uri.port, **http_opts) do |http|
        http.max_retries = 0 if http.respond_to?(:max_retries=)
        log_info("[Client #{client_index}] Connection established to #{uri.host}.")

        if @slowloris_delay.positive?
          run_slowloris_session(client_index, uri, http, start_time)
        else
          request = Net::HTTP::Get.new(uri)
          request['Connection'] = 'keep-alive'
          request['User-Agent'] = @user_agent
          @headers.each { |k, v| request[k] = v }

          http.request(request) do |response|
            response.read_body { |_chunk| nil }
          end

          loop do
            elapsed = Time.now - start_time
            if @keep_alive_timeout.positive? && elapsed >= @keep_alive_timeout
              log_info("[Client #{client_index}] Keep-alive timeout reached, closing.")
              break
            end

            if @qps_per_connection.positive?
              sleep(calculate_sleep(1.0 / @qps_per_connection))

              qps_request = Net::HTTP::Get.new(uri)
              qps_request['Connection'] = 'keep-alive'
              qps_request['User-Agent'] = @user_agent
              @headers.each { |k, v| qps_request[k] = v }

              response = http.request(qps_request) do |res|
                res.read_body { |_chunk| nil }
              end

              if @track_status_codes && !response.is_a?(Net::HTTPSuccess) && !response.is_a?(Net::HTTPRedirection)
                log_info("[Client #{client_index}] Upstream returned HTTP #{response.code}")
              end

              break unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
            elsif @ping
              sleep(calculate_sleep(@ping_period.to_f))
              ping_request = Net::HTTP::Head.new(uri)
              ping_request['Connection'] = 'keep-alive'
              ping_request['User-Agent'] = @user_agent
              @headers.each { |k, v| ping_request[k] = v }
              response = http.request(ping_request)

              if @track_status_codes && !response.is_a?(Net::HTTPSuccess) && !response.is_a?(Net::HTTPRedirection)
                log_info("[Client #{client_index}] Upstream returned HTTP #{response.code}")
              end

              break unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
            else
              # Hold loop open without pinging if keep_alive_timeout is set
              sleep(calculate_sleep(1.0))
            end
          end
        end
      end
      log_info("[Client #{client_index}] Connection gracefully closed.")
    rescue Errno::EMFILE => e
      log_error("[Client #{client_index}] ERROR_EMFILE: #{e.message}")
    rescue Errno::EADDRNOTAVAIL
      log_error("[Client #{client_index}] ERROR_EADDRNOTAVAIL: Ephemeral port limit reached.")
    rescue StandardError => e
      log_error("[Client #{client_index}] ERROR_OTHER: #{e.message}")
    end

    def build_http_opts(client_index, http_args)
      http_opts = http_args.dup
      http_opts[:local_host] = @bind_ips[client_index % @bind_ips.size] if @bind_ips.any?

      if @proxy_pool.any?
        proxy_uri = URI.parse(@proxy_pool[client_index % @proxy_pool.size])
        http_opts[:proxy_address] = proxy_uri.host
        http_opts[:proxy_port] = proxy_uri.port
        http_opts[:proxy_user] = proxy_uri.user if proxy_uri.user
        http_opts[:proxy_pass] = proxy_uri.password if proxy_uri.password
      end

      http_opts
    end

    def run_slowloris_session(client_index, uri, http, start_time)
      socket_wrapper = http.instance_variable_get(:@socket)
      return unless socket_wrapper

      io = socket_wrapper.io

      path = uri.path.empty? ? '/' : uri.path
      query = uri.query ? "?#{uri.query}" : ''
      payload = "GET #{path}#{query} HTTP/1.1\r\nHost: #{uri.host}\r\nConnection: keep-alive\r\nUser-Agent: #{@user_agent}\r\n"
      @headers.each { |k, v| payload += "#{k}: #{v}\r\n" }
      payload += 'X-Slowloris: ' # unfinished header

      payload.each_char do |char|
        io.write(char)
        io.flush
        sleep(calculate_sleep(@slowloris_delay))
      end

      # Eternal loop sending random garbage characters to keep thread open
      loop do
        elapsed = Time.now - start_time
        if @keep_alive_timeout.positive? && elapsed >= @keep_alive_timeout
          log_info("[Client #{client_index}] Keep-alive timeout reached, closing Slowloris thread.")
          break
        end

        io.write(rand(97..122).chr)
        io.flush
        sleep(calculate_sleep(@slowloris_delay))
      end
    end

    sig { params(message: String).void }
    def log_info(message)
      return unless @verbose

      # Rule compliance: Internal logging mechanisms must strictly default to UTC
      timestamp = Time.now.utc.iso8601
      @log_queue << [:info, "[#{timestamp}] #{message}"]
    end

    sig { params(message: String).void }
    def log_error(message)
      # Rule compliance: Internal logging mechanisms must strictly default to UTC
      timestamp = Time.now.utc.iso8601
      @log_queue << [:error, "[#{timestamp}] #{message}"]
    end
  end
end
