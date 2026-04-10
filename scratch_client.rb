# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'net/http'
require 'uri'
require 'openssl'
require 'async'
require 'async/semaphore'

module KeepAlive
  class Client
    extend T::Sig

    sig do
      params(
        connections: Integer,
        target_url: T.nilable(String),
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
        user_agent: String
      ).void
    end
    def initialize( # rubocop:disable Metrics/ParameterLists
      connections:, target_url: nil, use_https: false,
      verbose: false, ping: true, ping_period: 5,
      keep_alive_timeout: 0.0, connections_per_second: 0,
      max_concurrent_connections: 1000, reopen_closed_connections: false,
      reopen_interval: 1.0, read_timeout: 0.0, user_agent: 'Keep-Alive Test'
    )
      @connections = connections
      @target_url = target_url
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

      @uri = T.let(determine_uri, URI::Generic)
      @http_args = T.let(determine_http_args, T::Hash[Symbol, T.untyped])
      @protocol_label = T.let(determine_protocol_label, String)
      @error_log = T.let(Mutex.new, Mutex)
      @info_log = T.let(Mutex.new, Mutex)
    end

    sig { void }
    def start
      puts "[Client] Starting #{@connections} #{@protocol_label} connections to #{@uri}..."
      puts '[Client] Note: Output of individual pings is suppressed to avoid console spam.' unless @verbose

      trap('INT') { exit(0) }

      # Create/truncate log files deterministically
      File.write('client.err', '')
      File.write('client.log', '') if @verbose

      Async do |task|
        semaphore = Async::Semaphore.new(@max_concurrent_connections, parent: task)
        @connections.times do |i|
          task.sleep(1.0 / @connections_per_second) if @connections_per_second.positive?
          semaphore.async do
            execute_connection(i)
          end
        end
      end
    end

    private

    sig { returns(URI::Generic) }
    def determine_uri
      if @target_url
        URI(@target_url.to_s)
      elsif @use_https
        URI('https://localhost:8443')
      else
        URI('http://localhost:8080')
      end
    end

    sig { returns(String) }
    def determine_protocol_label
      if @target_url
        "EXTERNAL #{@uri.scheme&.upcase}"
      elsif @use_https
        'HTTPS'
      else
        'HTTP'
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def determine_http_args
      args = { read_timeout: @read_timeout.positive? ? @read_timeout : nil }
      if @uri.scheme == 'https'
        args.merge(use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE)
      else
        args
      end
    end

    sig { params(client_index: Integer).void }
    def execute_connection(client_index)
      start_time = Time.now

      loop do
        run_http_session(client_index, start_time)
        break unless @reopen_closed_connections

        # If we broke out and need to reopen, we sleep first
        sleep(@reopen_interval)
      end
    end

    sig { params(client_index: Integer, start_time: Time).void }
    def run_http_session(client_index, start_time)
      Net::HTTP.start(T.must(@uri.host), @uri.port, **@http_args) do |http|
        log_info("[Client #{client_index}] Connection established.")
        request = Net::HTTP::Get.new(@uri)
        request['Connection'] = 'keep-alive'
        request['User-Agent'] = @user_agent

        http.request(request) do |response|
          response.read_body { |_chunk| nil }
        end

        loop do
          elapsed = Time.now - start_time
          if @keep_alive_timeout.positive? && elapsed >= @keep_alive_timeout
            log_info("[Client #{client_index}] Keep-alive timeout reached, closing.")
            break
          end

          if @ping
            sleep(@ping_period)
            ping_request = Net::HTTP::Head.new(@uri)
            ping_request['Connection'] = 'keep-alive'
            ping_request['User-Agent'] = @user_agent
            response = http.request(ping_request)
            break unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
          else
            # Hold loop open without pinging if keep_alive_timeout is set
            sleep(1.0)
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

    sig { params(message: String).void }
    def log_info(message)
      return unless @verbose

      @info_log.synchronize do
        File.open('client.log', 'a') { |f| f.puts(message) }
      end
    end

    sig { params(message: String).void }
    def log_error(message)
      @error_log.synchronize do
        File.open('client.err', 'a') { |f| f.puts(message) }
      end
    end
  end
end
