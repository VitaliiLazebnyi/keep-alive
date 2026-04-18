# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'shellwords'

# Primary namespace for the load testing framework.
module HttpLoader
  class Harness
    # Manages child process lifecycles natively and checks status dynamically.
    class ProcessManager
      extend T::Sig

      sig { returns(T.nilable(Integer)) }
      attr_reader :server_pid, :client_pid

      # Allocates a new supervisor manager evaluating local child architectures natively.
      #
      # @param config [HttpLoader::Harness::Config] strongly typed harness runtime configurations
      # @return [void]
      sig { params(config: HttpLoader::Harness::Config).void }
      def initialize(config)
        @config = config
        @server_pid = T.let(nil, T.nilable(Integer))
        @client_pid = T.let(nil, T.nilable(Integer))
        @log_dir = T.let(File.expand_path('../../../logs', __dir__), String)
      end

      # Unilaterally forks background OS processes wiring explicit file descriptor capture bounds natively.
      #
      # @return [void]
      sig { void }
      def spawn_processes
        FileUtils.mkdir_p(@log_dir)
        spawn_server unless @config.target_urls.any?
        spawn_client
      end

      # Sweeps and securely terminates attached children upon trap signaling explicitly.
      #
      # @return [void]
      sig { void }
      def cleanup
        begin
          Process.kill('INT', @server_pid) if @server_pid
        rescue StandardError; nil
        end
        begin
          Process.kill('INT', @client_pid) if @client_pid
        rescue StandardError; nil
        end
      end

      # Resolves active PID statuses ensuring both mapped logic ends remain alive actively.
      #
      # @return [Boolean] true flag implying fatal termination of tracked underlying routines
      sig { returns(T::Boolean) }
      def missing_process?
        return true if @client_pid && dead?(@client_pid)
        return true if @server_pid && dead?(@server_pid)

        false
      end

      private

      # Triggers Ruby's async native wrapper bindings spawning local HTTP1 endpoints natively via falcon bounds.
      #
      # @return [void]
      sig { void }
      def spawn_server
        server_cmd = ['ruby', 'bin/http_loader', 'server']
        server_cmd << '--https' if @config.use_https
        @server_pid = Process.spawn(
          Shellwords.join(server_cmd), out: File.join(@log_dir, 'server.log'), err: File.join(@log_dir, 'server.err')
        )
        puts "[Harness] Started server with PID #{@server_pid}"
        sleep(2)
      end

      # Synthesizes child client threads pushing dynamic option mapping strictly.
      #
      # @return [void]
      sig { void }
      def spawn_client
        client_cmd = ['ruby', 'bin/http_loader', 'client']
        client_cmd += @config.client_args.empty? ? ["--connections_count=#{@config.connections}"] : @config.client_args

        @client_pid = Process.spawn(
          Shellwords.join(client_cmd), out: File.join(@log_dir, 'client.log'), err: File.join(@log_dir, 'client.err')
        )
        puts "[Harness] Started client with PID #{@client_pid}"
      end

      # Low-level POSIX call checking SIG status mapping logic externally.
      #
      # @param pid [Integer] system explicit PID string mapping
      # @return [Boolean] evaluation declaring mortality manually
      sig { params(pid: Integer).returns(T::Boolean) }
      def dead?(pid)
        Process.getpgid(pid)
        false
      rescue Errno::ESRCH
        true
      end
    end
  end
end
