# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  class Harness
    # Manages child process lifecycles natively and checks status dynamically.
    class ProcessManager
      extend T::Sig

      sig { returns(T.nilable(Integer)) }
      attr_reader :server_pid, :client_pid

      sig { params(config: KeepAlive::Harness::Config).void }
      def initialize(config)
        @config = config
        @server_pid = T.let(nil, T.nilable(Integer))
        @client_pid = T.let(nil, T.nilable(Integer))
        @log_dir = T.let(File.expand_path('../../../logs', __dir__), String)
      end

      sig { void }
      def spawn_processes
        FileUtils.mkdir_p(@log_dir)
        spawn_server unless @config.target_urls.any?
        spawn_client
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

      sig { returns(T::Boolean) }
      def missing_process?
        return true if @client_pid && dead?(@client_pid)
        return true if @server_pid && dead?(@server_pid)

        false
      end

      private

      sig { void }
      def spawn_server
        server_cmd = ['ruby', 'bin/keep_alive', 'server']
        server_cmd << '--https' if @config.use_https
        @server_pid = Process.spawn(*server_cmd, out: File.join(@log_dir, 'server.log'),
                                                 err: File.join(@log_dir, 'server.err'))
        puts "[Harness] Started server with PID #{@server_pid}"
        sleep(2)
      end

      sig { void }
      def spawn_client
        client_cmd = ['ruby', 'bin/keep_alive', 'client']
        client_cmd += @config.client_args.empty? ? ["--connections_count=#{@config.connections}"] : @config.client_args

        @client_pid = Process.spawn(*client_cmd, out: File.join(@log_dir, 'client.log'),
                                                 err: File.join(@log_dir, 'client.err'))
        puts "[Harness] Started client with PID #{@client_pid}"
      end

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
