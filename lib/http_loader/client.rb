# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'net/http'
require 'uri'
require 'openssl'
require 'async'
require 'async/semaphore'
require 'time'
require_relative 'client/config'
require_relative 'client/logger'
require_relative 'client/target_manager'
require_relative 'client/slowloris'
require_relative 'client/http_session'
require_relative 'client/error_handler'

# Primary namespace for the load testing framework.
module HttpLoader
  # Master client class coordinating connection pools through Async Engine.
  class Client
    extend T::Sig
    include ErrorHandler

    sig { returns(HttpLoader::Client::Logger) }
    attr_reader :logger

    # Initializes a new Client instance.
    #
    # @param config [Config] the strongly typed configuration object
    # @return [void]
    sig { params(config: Config).void }
    def initialize(config)
      @config = T.let(config, Config)
      @logger = T.let(Logger.new(config.verbose), Logger)
      @target_manager = T.let(TargetManager.new(config), TargetManager)
      @slow_sess = T.let(Slowloris.new(config, @logger), Slowloris)
      @http_sess = T.let(HttpSession.new(config, @logger), HttpSession)
    end

    # Starts the load generation engine and applies trap handlers.
    #
    # @return [void]
    sig { void }
    def start
      log_startup_message
      trap('INT') { exit(0) }
      @logger.setup_files!

      Async { |raw_task| run_engine(T.cast(raw_task, Async::Task)) }
    ensure
      @logger.flush_synchronously!
    end

    private

    # Runs the asynchronous task engine spawning connections.
    #
    # @param task [Async::Task] the async orchestration task
    # @return [void]
    sig { params(task: Async::Task).void }
    def run_engine(task)
      logger_t = @logger.run_task(task)
      sem = Async::Semaphore.new(@config.max_concurrent_connections, parent: task)

      conn_tasks = T.let([], T::Array[Async::Task])
      @config.connections.times do |raw_i|
        i = raw_i
        perform_sleep(calc_ramp, task: task) if calc_ramp.positive?
        conn_tasks << sem.async { exec_conn(i) }
      end

      conn_tasks.each(&:wait)
      logger_t.stop
    end

    # Prints the initialization banner to stdout.
    #
    # @return [void]
    sig { void }
    def log_startup_message
      @logger.info("Starting #{@config.connections} #{@target_manager.protocol_label} connections")
      puts "[Client] Starting #{@config.connections} #{@target_manager.protocol_label} connections to targeted urls..."
      puts '[Client] Note: Output of individual pings is suppressed.' unless @config.verbose
    end

    # Calculates the sleep duration required for ramp-up.
    #
    # @return [Float] the calculated ramp sleep duration
    sig { returns(Float) }
    def calc_ramp
      if @config.ramp_up.positive?
        @config.ramp_up.to_f / @config.connections
      elsif @config.connections_per_second.positive?
        1.0 / @config.connections_per_second
      else
        0.0
      end
    end

    # Executes sleep logic during ramp-up phases.
    #
    # @param dur [Float] the duration to sleep
    # @param task [Async::Task, nil] the async task if running within engine
    # @return [void]
    sig { params(dur: Float, task: T.nilable(Async::Task)).void }
    def perform_sleep(dur, task: nil)
      task ? task.sleep(dur) : sleep(dur)
    end

    # Applies randomization jitter to the base sleep interval.
    #
    # @param base [Float] the base sleep interval
    # @return [Float] the jittered interval
    sig { params(base: Float).returns(Float) }
    def calc_sleep(base)
      return base if @config.jitter.zero?

      v = base * @config.jitter
      [0.0, base + rand(-v..v)].max
    end

    # Continuously attempts connection runs per thread/worker.
    #
    # @param idx [Integer] the connection identifier
    # @return [void]
    sig { params(idx: Integer).void }
    def exec_conn(idx)
      loop do
        run_session(idx, Time.now)
        break unless @config.reopen_closed_connections

        sleep(calc_sleep(@config.reopen_interval))
      end
    end

    # Sets up a single HTTP session to the target uri.
    #
    # @param idx [Integer] the connection identifier
    # @param start_t [Time] the invocation timestamp
    # @return [void]
    sig { params(idx: Integer, start_t: Time).void }
    def run_session(idx, start_t)
      ctx = @target_manager.context_for(idx)
      uri = T.cast(ctx[:uri], URI::Generic)

      start_http(uri, fetch_opts(idx, ctx)) do |http|
        http.max_retries = 0 if http.respond_to?(:max_retries=)
        @logger.info("[Client #{idx}] Connection established to #{uri.host}.")
        dispatch_sess(idx, uri, http, start_t)
      end
      @logger.info("[Client #{idx}] Connection gracefully closed.")
    rescue StandardError => e
      handle_err(idx, e)
    end

    # Fetches final connection contexts from TargetManager.
    #
    # @param idx [Integer] the connection identifier
    # @param ctx [Hash] the partial context map
    # @return [Hash] the fully resolved HTTP start arguments
    sig { params(idx: Integer, ctx: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def fetch_opts(idx, ctx)
      args = T.cast(ctx[:http_args], T::Hash[Symbol, T.untyped])
      @target_manager.http_opts_for(idx, args)
    end

    # Wraps the synchronous net-http start call with a block closure.
    #
    # @param uri [URI::Generic] the target generic uri
    # @param opts [Hash] injected configuration options for HTTP
    # @param block [Proc] yieldable closure receiving HTTP connection instantiated
    # @return [void]
    sig { params(uri: URI::Generic, opts: T::Hash[Symbol, T.untyped], block: T.proc.params(arg: Net::HTTP).void).void }
    def start_http(uri, opts, &block)
      Net::HTTP.start(T.must(uri.host), uri.port, **opts, &block)
    end

    # Dispatches the authenticated connection stream to the active protocol implementation.
    #
    # @param idx [Integer] the connection identifier
    # @param uri [URI::Generic] the generic target uri
    # @param http [Net::HTTP] the instantiated active connection session
    # @param start_t [Time] the lifecycle timestamp of the execution block
    # @return [void]
    sig { params(idx: Integer, uri: URI::Generic, http: Net::HTTP, start_t: Time).void }
    def dispatch_sess(idx, uri, http, start_t)
      if @config.slowloris_delay.positive?
        @slow_sess.run(idx, uri, http, start_t)
      else
        @http_sess.run(idx, uri, http, start_t)
      end
    end
  end
end
