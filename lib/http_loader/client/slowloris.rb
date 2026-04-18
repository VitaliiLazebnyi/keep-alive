# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

# Primary namespace for the load testing framework.
module HttpLoader
  class Client
    # Handles deliberate thread-hogging Slowloris tactics.
    class Slowloris
      extend T::Sig

      # Builds the slowloris execution strategy instance.
      #
      # @param config [Config] the validated config parameters
      # @param logger [Logger] the isolated asynchronous log context
      # @return [void]
      sig { params(config: Config, logger: Logger).void }
      def initialize(config, logger)
        @config = T.let(config, Config)
        @logger = T.let(logger, Logger)
      end

      # Engages the slowloris thread hold directly manipulating the raw socket bypassing HTTP standards.
      #
      # @param client_index [Integer] numeric unique identifier for this virtual client
      # @param uri [URI::Generic] the parsed target destination
      # @param http [Net::HTTP] instantiated http connection payload
      # @param start_time [Time] context timestamp determining lifespan violations
      # @return [void]
      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP, start_time: Time).void }
      def run(client_index, uri, http, start_time)
        return unless @config.slowloris_delay > 0.0

        socket_wrapper = T.cast(http.instance_variable_get(:@socket), T.nilable(Net::BufferedIO))
        return unless socket_wrapper

        io = socket_wrapper.io
        fire_initial_payload(io, uri)
        maintain_hold(client_index, io, start_time)
      end

      private

      # Writes the HTTP payload character by character with configurable artificial delay constraints.
      #
      # @param io [IO] the physical IO bound socket instance
      # @param uri [URI::Generic] the targeted request identifier
      # @return [void]
      sig { params(io: IO, uri: URI::Generic).void }
      def fire_initial_payload(io, uri)
        payload = build_payload_headers(uri)

        payload.each_char do |char|
          io.write(char)
          io.flush
          sleep(calculate_sleep(@config.slowloris_delay))
        end
      end

      # Crafts the raw text representing a completely viable HTTP/1.1 payload excluding finalizing line-breaks.
      #
      # @param uri [URI::Generic] the targeted parameters identifier
      # @return [String] the string representation of an artificially incomplete payload request
      sig { params(uri: URI::Generic).returns(String) }
      def build_payload_headers(uri)
        path = T.must(uri.path).empty? ? '/' : uri.path
        query = uri.query ? "?#{uri.query}" : ''
        payload = "GET #{path}#{query} HTTP/1.1\r\n" \
                  "Host: #{uri.host}\r\n" \
                  "Connection: keep-alive\r\n" \
                  "User-Agent: #{@config.user_agent}\r\n"
        @config.headers.each { |k, v| payload += "#{k}: #{v}\r\n" }
        payload += 'X-Slowloris: ' # unfinished header
        payload
      end

      # Keeps an ongoing socket indefinitely occupied via sporadic random byte injection.
      #
      # @param client_index [Integer] numeric connection index used by logging
      # @param io [IO] underlying network IO byte writer
      # @param start_time [Time] lifecycle origination period
      # @return [void]
      sig { params(client_index: Integer, io: IO, start_time: Time).void }
      def maintain_hold(client_index, io, start_time)
        loop do
          elapsed = Time.now - start_time
          if @config.http_loader_timeout > 0.0 && elapsed >= @config.http_loader_timeout
            @logger.info("[Client #{client_index}] Keep-alive timeout reached, closing Slowloris thread.")
            break
          end

          io.write(rand(97..122).chr)
          io.flush
          sleep(calculate_sleep(@config.slowloris_delay))
        end
      end

      # Analyzes base sleep threshold utilizing configured global jitter factors.
      #
      # @param base_seconds [Float] the strict numerical sleep request
      # @return [Float] randomly dispersed sleep interval ensuring asynchronous collisions do not align
      sig { params(base_seconds: Float).returns(Float) }
      def calculate_sleep(base_seconds)
        return base_seconds if @config.jitter.zero?

        variance = base_seconds * @config.jitter
        [0.0, base_seconds + rand(-variance..variance)].max
      end
    end
  end
end
