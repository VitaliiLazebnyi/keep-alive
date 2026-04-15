# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module KeepAlive
  class Client
    # ErrorHandler provides error handling strategies natively.
    module ErrorHandler
      extend T::Sig
      extend T::Helpers

      requires_ancestor { KeepAlive::Client }

      sig { params(idx: Integer, err: StandardError).void }
      def handle_err(idx, err)
        case err
        when Errno::EMFILE
          @logger.error("[Client #{idx}] ERROR_EMFILE: #{err.message}")
        when Errno::EADDRNOTAVAIL
          @logger.error("[Client #{idx}] ERROR_EADDRNOTAVAIL: Ephemeral port limit reached.")
        else
          @logger.error("[Client #{idx}] ERROR_OTHER: #{err.message}")
        end
      end
    end
  end
end
