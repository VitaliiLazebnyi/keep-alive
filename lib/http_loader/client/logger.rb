# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'fileutils'
require 'time'

# Primary namespace for the load testing framework.
module HttpLoader
  class Client
    # Handles asynchronous file logging to prevent blocking main connections.
    class Logger
      extend T::Sig

      # Initializes a new Logger instance, creating internal queues for asynchronous work.
      #
      # @param verbose [Boolean] enables verbose terminal logging
      # @return [void]
      sig { params(verbose: T::Boolean).void }
      def initialize(verbose)
        @verbose = verbose
        @log_dir = T.let(File.expand_path('../../../logs', __dir__), String)
        @log_queue = T.let(Queue.new, Queue)
        @logger_task = T.let(nil, Object)
      end

      # Prepares the filesystem by creating necessary log files and clearing previous logs.
      #
      # @return [void]
      sig { void }
      def setup_files!
        FileUtils.mkdir_p(@log_dir)
        File.write(File.join(@log_dir, 'client.err'), '')
        File.write(File.join(@log_dir, 'client.log'), '') if @verbose
      end

      # Spins up an async listener mapping log queues to the underlying file descriptors.
      #
      # @param task [Object] the orchestration asynchronous task
      # @return [Object] the running logger task yielding IO operations
      sig { params(task: Async::Task).returns(Async::Task) }
      def run_task(task)
        @logger_task = task.async do
          File.open(File.join(@log_dir, 'client.log'), 'a') do |log|
            File.open(File.join(@log_dir, 'client.err'), 'a') do |err|
              poll_queue(task, log, err)
            end
          end
        end
        T.cast(@logger_task, Async::Task)
      end

      # Safely drains remaining log entries to disk synchronously when engine exits.
      #
      # @return [void]
      sig { void }
      def flush_synchronously!
        File.open(File.join(@log_dir, 'client.log'), 'a') do |log|
          File.open(File.join(@log_dir, 'client.err'), 'a') do |err|
            drain_queue(log, err)
          end
        end
      rescue StandardError
        nil
      end

      # Enqueues general informative messages to the async log queue if verbose flag is toggled.
      #
      # @param message [String] the formatted payload message
      # @return [void]
      sig { params(message: String).void }
      def info(message)
        return unless @verbose

        # ! SORBET BYPASS: Queue push allows Object
        @log_queue << [:info, "[#{Time.now.utc.iso8601}] #{message}"]
      end

      # Enqueues error messages immediately irrespective of verbosity configuration.
      #
      # @param message [String] the formatted payload message
      # @return [void]
      sig { params(message: String).void }
      def error(message)
        # ! SORBET BYPASS: Queue push allows Object
        @log_queue << [:error, "[#{Time.now.utc.iso8601}] #{message}"]
      end

      private

      # Consumes queue actively via block polling using async sleeping paradigms.
      #
      # @param task [Object] the orchestrator bound task
      # @param log [File] descriptor targeting the info/debug log
      # @param err [File] descriptor targeting the error log
      # @return [void]
      sig { params(task: Async::Task, log: File, err: File).void }
      def poll_queue(task, log, err)
        loop do
          msg = fetch_message(task)
          next unless msg
          break if msg == :terminate

          write_msg(T.cast(msg, T::Array[T.any(Symbol, String)]), log, err)
        end
      end

      # Continuously forces buffer evaluation synchronously without yielding runtime.
      #
      # @param log [File] descriptor targeting the info/debug log
      # @param err [File] descriptor targeting the error log
      # @return [void]
      sig { params(log: File, err: File).void }
      def drain_queue(log, err)
        loop do
          popped = begin; @log_queue.pop(true); rescue ThreadError; nil; end
          msg_raw = T.cast(popped, T.nilable(T.any(Symbol, T::Array[T.any(Symbol, String)])))
          break unless msg_raw

          msg = msg_raw
          break if msg == :terminate

          write_msg(T.cast(msg, T::Array[T.any(Symbol, String)]), log, err)
        end
      end

      # Tries popping elements off execution queues non-blockingly, sleeping async if empty.
      #
      # @param task [Object] the async orchestrator task
      # @return [T.nilable(T.any(Symbol, T::Array[T.any(Symbol, String)]))] the payload tuple, termination symbol, or nil
      sig { params(task: Async::Task).returns(T.nilable(T.any(Symbol, T::Array[T.any(Symbol, String)]))) }
      def fetch_message(task)
        msg_raw = @log_queue.pop(true)
        T.cast(msg_raw, T.any(Symbol, T::Array[T.any(Symbol, String)]))
      rescue ThreadError
        task.sleep(0.05)
        nil
      end

      # Evaluates payload structure formatting raw string to physical IO devices.
      #
      # @param msg [Array<T.any(Symbol, String)>] the log level tuple targeting IO
      # @param log [File] descriptor targeting the info/debug log
      # @param err [File] descriptor targeting the error log
      # @return [void]
      sig { params(msg: T::Array[T.any(Symbol, String)], log: File, err: File).void }
      def write_msg(msg, log, err)
        target, content = msg
        target = T.cast(target, Symbol)
        content_str = T.cast(content, String)
        if target == :info
          log.puts content_str
          log.flush
        elsif target == :error
          err.puts content_str
          err.flush
        end
      end
    end
  end
end
