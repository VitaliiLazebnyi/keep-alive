# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'net/http'

module KeepAlive
  class Client
    # Handles normal and QPS-driven HTTP keep-alive connections.
    class HttpSession
      extend T::Sig

      sig { params(config: Config, logger: Logger).void }
      def initialize(config, logger)
        @config = config
        @logger = logger
      end

      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP, start_time: Time).void }
      def run(client_index, uri, http, start_time)
        return if @config.slowloris_delay.positive?

        fire_initial_request(uri, http)
        maintain_keepalive(client_index, uri, http, start_time)
      end

      private

      sig { params(uri: URI::Generic, http: Net::HTTP).void }
      def fire_initial_request(uri, http)
        request = Net::HTTP::Get.new(uri)
        request['Connection'] = 'keep-alive'
        request['User-Agent'] = @config.user_agent
        @config.headers.each { |k, v| request[k] = v }

        http.request(request) do |response|
          response.read_body { |_chunk| nil }
        end
      end

      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP, start_time: Time).void }
      def maintain_keepalive(client_index, uri, http, start_time)
        loop do
          elapsed = Time.now - start_time
          if @config.keep_alive_timeout.positive? && elapsed >= @config.keep_alive_timeout
            @logger.info("[Client #{client_index}] Keep-alive timeout reached, closing.")
            break
          end

          break unless process_heartbeat?(client_index, uri, http)
        end
      end

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

      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP).returns(T::Boolean) }
      def perform_qps?(client_index, uri, http)
        sleep(calculate_sleep(1.0 / @config.qps_per_connection))
        req = build_request(Net::HTTP::Get.new(uri))

        res = http.request(req) do |r|
          r.read_body { |_c| nil }
        end
        log_status(client_index, res)
        success?(res)
      end

      sig { params(client_index: Integer, uri: URI::Generic, http: Net::HTTP).returns(T::Boolean) }
      def perform_ping?(client_index, uri, http)
        sleep(calculate_sleep(@config.ping_period.to_f))
        req = build_request(Net::HTTP::Head.new(uri))

        res = http.request(req)
        log_status(client_index, res)
        success?(res)
      end

      sig { params(req: Net::HTTPRequest).returns(Net::HTTPRequest) }
      def build_request(req)
        req['Connection'] = 'keep-alive'
        req['User-Agent'] = @config.user_agent
        @config.headers.each { |k, v| req[k] = v }
        req
      end

      sig { params(res: Net::HTTPResponse).returns(T::Boolean) }
      def success?(res)
        res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection)
      end

      sig { params(client_index: Integer, res: Net::HTTPResponse).void }
      def log_status(client_index, res)
        return unless @config.track_status_codes
        return if success?(res)

        @logger.info("[Client #{client_index}] Upstream returned HTTP #{res.code}")
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
