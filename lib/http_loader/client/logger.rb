# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'fileutils'
require 'time'

module KeepAlive
  class Client
    # Handles asynchronous file logging to prevent blocking main connections.
    class Logger
      extend T::Sig

      sig { params(verbose: T::Boolean).void }
      def initialize(verbose)
        @verbose = verbose
        @log_dir = T.let(File.expand_path('../../../logs', __dir__), String)
        @log_queue = T.let(Queue.new, Queue)
        @logger_task = T.let(nil, T.nilable(T.untyped))
      end

      sig { void }
      def setup_files!
        FileUtils.mkdir_p(@log_dir)
        File.write(File.join(@log_dir, 'client.err'), '')
        File.write(File.join(@log_dir, 'client.log'), '') if @verbose
      end

      sig { params(task: T.untyped).returns(T.untyped) }
      def run_task(task)
        @logger_task = task.async do
          File.open(File.join(@log_dir, 'client.log'), 'a') do |log|
            File.open(File.join(@log_dir, 'client.err'), 'a') do |err|
              poll_queue(task, log, err)
            end
          end
        end
      end

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

      sig { params(message: String).void }
      def info(message)
        return unless @verbose

        @log_queue << [:info, "[#{Time.now.utc.iso8601}] #{message}"]
      end

      sig { params(message: String).void }
      def error(message)
        @log_queue << [:error, "[#{Time.now.utc.iso8601}] #{message}"]
      end

      private

      sig { params(task: T.untyped, log: File, err: File).void }
      def poll_queue(task, log, err)
        loop do
          msg = fetch_message(task)
          next unless msg
          break if msg == :terminate

          write_msg(msg, log, err)
        end
      end

      sig { params(log: File, err: File).void }
      def drain_queue(log, err)
        loop do
          msg = begin
            @log_queue.pop(true)
          rescue ThreadError
            nil
          end
          break unless msg && msg != :terminate

          write_msg(msg, log, err)
        end
      end

      sig { params(task: T.untyped).returns(T.untyped) }
      def fetch_message(task)
        @log_queue.pop(true)
      rescue ThreadError
        task.sleep(0.05)
        nil
      end

      sig { params(msg: T::Array[T.untyped], log: File, err: File).void }
      def write_msg(msg, log, err)
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
