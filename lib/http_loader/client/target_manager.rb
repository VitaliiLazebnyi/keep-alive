# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'
require 'uri'
require 'socket'

module KeepAlive
  class Client
    # Manages URI contexts, IPs, proxies, and HTTPS resolution.
    class TargetManager
      extend T::Sig

      sig { params(config: Config).void }
      def initialize(config)
        @config = config
        @target_contexts = T.let(build_target_contexts, T::Array[T::Hash[Symbol, T.untyped]])
      end

      sig { returns(String) }
      def protocol_label
        if @config.target_urls.size > 1
          "MULTIPLE TARGETS (#{@config.target_urls.size})"
        elsif @config.target_urls.size == 1
          "EXTERNAL #{T.cast(T.must(@target_contexts.first)[:uri], URI::Generic).scheme&.upcase}"
        elsif @config.use_https
          'HTTPS'
        else
          'HTTP'
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def contexts
        @target_contexts
      end

      sig { params(client_index: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def context_for(client_index)
        T.must(@target_contexts[client_index % @target_contexts.size])
      end

      sig { params(client_index: Integer, args: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def http_opts_for(client_index, args)
        http_opts = args.dup
        bind_ips = @config.bind_ips
        http_opts[:local_host] = bind_ips[client_index % bind_ips.size] if bind_ips.any?

        apply_proxy!(http_opts, client_index) if @config.proxy_pool.any?
        http_opts
      end

      sig { params(opts: T::Hash[Symbol, T.untyped], client_index: Integer).void }
      def apply_proxy!(opts, client_index)
        pool = @config.proxy_pool
        proxy_uri = URI.parse(pool[client_index % pool.size])
        opts[:proxy_address] = proxy_uri.host
        opts[:proxy_port] = proxy_uri.port
        opts[:proxy_user] = proxy_uri.user if proxy_uri.user
        opts[:proxy_pass] = proxy_uri.password if proxy_uri.password
      end

      private

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def build_target_contexts
        urls = @config.target_urls.any? ? @config.target_urls : [nil]
        urls.map do |url|
          uri = parse_uri(url)
          args = { read_timeout: @config.read_timeout.positive? ? @config.read_timeout : nil }
          args[:ipaddr] = resolve_ip(uri)
          { uri: uri, http_args: secure_opts(uri, args) }
        end
      end

      sig { params(url: T.nilable(String)).returns(URI::Generic) }
      def parse_uri(url)
        return URI(url.to_s) if url

        @config.use_https ? URI('https://localhost:8443') : URI('http://localhost:8080')
      end

      sig { params(uri: URI::Generic).returns(T.nilable(String)) }
      def resolve_ip(uri)
        ip_info = Addrinfo.getaddrinfo(T.must(uri.host), uri.port, nil, :STREAM)
        (ip_info.find(&:ipv4?) || ip_info.first)&.ip_address
      rescue SocketError
        nil
      end

      sig { params(uri: URI::Generic, args: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def secure_opts(uri, args)
        return args unless uri.scheme == 'https'

        args.merge(use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE)
      end
    end
  end
end
