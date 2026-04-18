# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'net/http'

# Primary namespace for the load testing framework.
module HttpLoader
  class Client
    # Handles normal and QPS-driven HTTP keep-alive connections.
    class HttpSession
      extend T::Sig

      # Constructs a new HTTP pooling session instance.
      #
      # @param config [Config] core runtime rules configuration
      # @param logger [Logger] the thread-safe async logger context
      # @return [void]
      sig { params(config: Config, logger: Logger).void }
      def initialize(config, logger)
        @config = T.let(config, Config)
        @logger = T.let(logger, Logger)
      end

      # Executes a standard compliant keep-alive pipeline.
      #
      # @param client_index [Integer] numeric connection index
      # @param uri [URI::Generic] targeted network address
      # @param http [Net::HTTP] the instantiated active connection session
      # @param start_time [Time] lifecycle originating timestamp
      # @return [void]
      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP, start_time: Time).void }
      def run(client_index, uri, http, start_time)
        return if @config.slowloris_delay.positive?

        fire_initial_request(uri, http)
        maintain_keepalive(client_index, uri, http, start_time)
      end

      private

      # Forms and dispenses the initial GET payload initiating standard interactions.
      #
      # @param uri [URI::Generic] endpoint structure target
      # @param http [Net::HTTP] open physical connection pipe
      # @return [void]
      sig { params(uri: URI::Generic, http: Net::HTTP).void }
      def fire_initial_request(uri, http)
        request = Net::HTTP::Get.new(uri)
        request['Connection'] = 'keep-alive'
        request['User-Agent'] = @config.user_agent
        @config.headers.each { |k, v| request[k] = v }

        http.request(request) do |raw_response|
          response = T.cast(raw_response, Net::HTTPResponse)
          response.read_body { |_chunk| nil }
        end
      end

      # Occupies the lifecycle constraint of the connection honoring periodic heartbeats.
      #
      # @param client_index [Integer] numeric tracking id
      # @param uri [URI::Generic] requested network destination
      # @param http [Net::HTTP] socket persistence wrapper
      # @param start_time [Time] initial cycle spawn stamp
      # @return [void]
      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP, start_time: Time).void }
      def maintain_keepalive(client_index, uri, http, start_time)
        loop do
          elapsed = Time.now - start_time
          if @config.http_loader_timeout.positive? && elapsed >= @config.http_loader_timeout
            @logger.info("[Client #{client_index}] Keep-alive timeout reached, closing.")
            break
          end

          break unless process_heartbeat?(client_index, uri, http)
        end
      end

      # Analyzes global configurations selecting appropriate recurrent payloads or static hibernation.
      #
      # @param client_index [Integer] numeric thread marker
      # @param uri [URI::Generic] destination configuration struct
      # @param http [Net::HTTP] active outbound resource allocation
      # @return [Boolean] returns true to perpetuate cycle, false to break and exit
      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP).returns(T::Boolean) }
      def process_heartbeat?(client_index, uri, http)
        if @config.qps_per_connection.positive?
          perform_qps?(client_index, uri, http)
        elsif @config.ping
          perform_ping?(client_index, uri, http)
        else
          sleep(calculate_sleep(1.0))
          true
        end
      end

      # Engages the aggressive QPS specific payload strategy generating verifiable load.
      #
      # @param client_index [Integer] the numeric id of the async block
      # @param uri [URI::Generic] active configuration struct parameters
      # @param http [Net::HTTP] live outgoing data streams
      # @return [Boolean] success logic representing connection continuation validation
      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP).returns(T::Boolean) }
      def perform_qps?(client_index, uri, http)
        sleep(calculate_sleep(1.0 / @config.qps_per_connection))
        req = build_request(Net::HTTP::Get.new(uri))

        res = T.cast(http.request(req) do |raw_r|
          T.cast(raw_r, Net::HTTPResponse).read_body { |_c| nil }
        end, Net::HTTPResponse)
        log_status(client_index, res)
        success?(res)
      end

      # Engages lightweight HEAD requests preserving network connection validity without excessive load.
      #
      # @param client_index [Integer] async boundary ID
      # @param uri [URI::Generic] the targeted struct params
      # @param http [Net::HTTP] executing communication object
      # @return [Boolean] true predicting session extension
      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP).returns(T::Boolean) }
      def perform_ping?(client_index, uri, http)
        sleep(calculate_sleep(@config.ping_period.to_f))
        req = build_request(Net::HTTP::Head.new(uri))

        res = T.cast(http.request(req), Net::HTTPResponse)
        log_status(client_index, res)
        success?(res)
      end

      # Injects standard headers and authentication markers onto the raw built payload.
      #
      # @param req [Net::HTTPRequest] un-augmented HTTP schema struct
      # @return [Net::HTTPRequest] configured representation ready for broadcast
      sig { params(req: Net::HTTPRequest).returns(Net::HTTPRequest) }
      def build_request(req)
        req['Connection'] = 'keep-alive'
        req['User-Agent'] = @config.user_agent
        @config.headers.each { |k, v| req[k] = v }
        req
      end

      # Validates protocol standards ensuring endpoints resolve correctly under pressure.
      #
      # @param res [Net::HTTPResponse] finalized return payload from load target
      # @return [Boolean] true denoting valid functional response patterns
      sig { params(res: Net::HTTPResponse).returns(T::Boolean) }
      def success?(res)
        res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
      end

      # Publishes diagnostic logs for HTTP non-compliant codes if tracking is enabled.
      #
      # @param client_index [Integer] connection identifying int
      # @param res [Net::HTTPResponse] HTTP output interface
      # @return [void]
      sig { params(client_index: Integer, res: Net::HTTPResponse).void }
      def log_status(client_index, res)
        return unless @config.track_status_codes
        return if success?(res)

        @logger.info("[Client #{client_index}] Upstream returned HTTP #{res.code}")
      end

      # Determines physical sleep timer using standard pseudo-random distributions.
      #
      # @param base_seconds [Float] minimum strict boundary logic
      # @return [Float] processed output accommodating jitter configurations
      sig { params(base_seconds: Float).returns(Float) }
      def calculate_sleep(base_seconds)
        return base_seconds if @config.jitter.zero?

        variance = base_seconds * @config.jitter
        [0.0, base_seconds + rand(-variance..variance)].max
      end
    end
  end
end
