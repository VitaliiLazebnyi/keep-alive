# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'json'

# Primary namespace for the load testing framework.
module HttpLoader
  class Harness
    # Exports telemetry and logs bottlenecks asynchronously and synchronously at termination.
    class Telemetry
      extend T::Sig

      # Mounts the telemetry sub-engine mapping disk outputs transparently tracking boundaries.
      #
      # @param log_dir [String] physical absolute path targeting output payload maps
      # @param export_json [String, nil] absolute file destination serializing end report dynamically
      # @return [void]
      sig { params(log_dir: String, export_json: T.nilable(String)).void }
      def initialize(log_dir, export_json)
        @log_dir = log_dir
        @export_json = export_json
      end

      # Serializes a comprehensive analysis payload upon successful OS termination manually.
      #
      # @param peak_connections [Integer] the high watermark metric for total alive states recorded
      # @param start_time [Time] chronological tracking root reference explicitly
      # @return [void]
      sig { params(peak_connections: Integer, start_time: Time).void }
      def export!(peak_connections, start_time)
        return unless @export_json

        payload = generate_payload(peak_connections, start_time, count_bottlenecks(read_logs))
        File.write(@export_json, JSON.generate(payload))
        puts "[Harness] Telemetry JSON securely sinked to #{@export_json}."
      end

      # Verifies local file output queues alerting std-out upon bottleneck OS detections actively.
      #
      # @return [void]
      sig { void }
      def check_bottlenecks!
        errors = build_bottleneck_messages(count_bottlenecks(read_logs))
        puts format('   => BOTTLENECK ACTIVE: %s', errors.join(' | ')) if errors.any?
      rescue StandardError
        nil
      end

      private

      # Formats an agnostic JSON hash representation mapping performance and anomalies universally.
      #
      # @param peak [Integer] logical max connections integer evaluation
      # @param start [Time] process baseline boot parameter mapping
      # @param counts [Hash] dictionary capturing parsed string evaluations tracking OS limits natively
      # @return [Hash] JSON translatable dataset mapping
      sig { params(peak: Integer, start: Time, counts: T::Hash[Symbol, Integer]).returns(T::Hash[Symbol, T.untyped]) }
      def generate_payload(peak, start, counts)
        {
          peak_connections: peak, test_duration_seconds: (Time.now.utc - start).round(2),
          errors: { emfile: counts[:emfile], eaddrnotavail: counts[:eaddr_count], thread_limit: counts[:thread_errors] }
        }
      end

      # Non-blockingly extracts physical log datasets without triggering process mutex collisions inherently.
      #
      # @return [String] unified payload log text evaluation directly read via native APIs
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

      # Aggregates instances of catastrophic OS limitations preventing linear load progressions proactively.
      #
      # @param log_text [String] aggregated string mapping log states
      # @return [Hash] subset defining statistical integer maps representing specific crashes
      sig { params(log_text: String).returns(T::Hash[Symbol, Integer]) }
      def count_bottlenecks(log_text)
        {
          emfile: log_text.scan('ERROR_EMFILE').size,
          eaddr_count: log_text.scan('ERROR_EADDRNOTAVAIL').size,
          thread_errors: log_text.scan('ERROR_THREADLIMIT').size
        }
      end

      # Translates generic error logs into explicit formatting tuples suitable for interactive terminals locally.
      #
      # @param counts [Hash] quantitative mapping metrics describing error boundaries natively
      # @return [Array<String>] textual output logs targeting stderr mapped explicitly
      sig { params(counts: T::Hash[Symbol, Integer]).returns(T::Array[String]) }
      def build_bottleneck_messages(counts)
        errors = []
        errors << "[OS FDs Limit: #{counts[:emfile]} EMFILE]" if T.must(counts[:emfile]).positive?
        errors << "[OS Ports Limit: #{counts[:eaddr_count]} EADDRNOTAVAIL]" if T.must(counts[:eaddr_count]).positive?
        errors << "[OS Thread Limit: #{counts[:thread_errors]} ThreadError]" if T.must(counts[:thread_errors]).positive?
        errors
      end
    end
  end
end
