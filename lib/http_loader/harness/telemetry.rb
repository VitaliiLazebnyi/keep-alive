# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'

module KeepAlive
  class Harness
    # Exports telemetry and logs bottlenecks asynchronously and synchronously at termination.
    class Telemetry
      extend T::Sig

      sig { params(log_dir: String, export_json: T.nilable(String)).void }
      def initialize(log_dir, export_json)
        @log_dir = log_dir
        @export_json = export_json
      end

      sig { params(peak_connections: Integer, start_time: Time).void }
      def export!(peak_connections, start_time)
        return unless @export_json

        payload = generate_payload(peak_connections, start_time, count_bottlenecks(read_logs))
        File.write(@export_json, JSON.generate(payload))
        puts "[Harness] Telemetry JSON securely sinked to #{@export_json}."
      end

      sig { void }
      def check_bottlenecks!
        errors = build_bottleneck_messages(count_bottlenecks(read_logs))
        puts format('   => BOTTLENECK ACTIVE: %s', errors.join(' | ')) if errors.any?
      rescue StandardError
        nil
      end

      private

      sig { params(peak: Integer, start: Time, counts: T::Hash[Symbol, Integer]).returns(T::Hash[Symbol, T.untyped]) }
      def generate_payload(peak, start, counts)
        {
          peak_connections: peak, test_duration_seconds: (Time.now.utc - start).round(2),
          errors: { emfile: counts[:emfile], eaddrnotavail: counts[:eaddr_count], thread_limit: counts[:thread_errors] }
        }
      end

      sig { returns(String) }
      def read_logs
        begin
          File.read(File.join(@log_dir, 'client.log'))
        rescue StandardError; ''
        end + begin
          File.read(File.join(@log_dir, 'client.err'))
        rescue StandardError; ''
        end
      end

      sig { params(log_text: String).returns(T::Hash[Symbol, Integer]) }
      def count_bottlenecks(log_text)
        {
          emfile: log_text.scan('ERROR_EMFILE').size,
          eaddr_count: log_text.scan('ERROR_EADDRNOTAVAIL').size,
          thread_errors: log_text.scan('ERROR_THREADLIMIT').size
        }
      end

      sig { params(counts: T::Hash[Symbol, Integer]).returns(T::Array[String]) }
      def build_bottleneck_messages(counts)
        errors = []
        errors << "[OS FDs Limit: #{counts[:emfile]} EMFILE]" if counts[:emfile].positive?
        errors << "[OS Ports Limit: #{counts[:eaddr_count]} EADDRNOTAVAIL]" if counts[:eaddr_count].positive?
        errors << "[OS Thread Limit: #{counts[:thread_errors]} ThreadError]" if counts[:thread_errors].positive?
        errors
      end
    end
  end
end
