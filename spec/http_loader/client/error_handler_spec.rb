# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/client'
require 'http_loader/client/error_handler'

RSpec.describe HttpLoader::Client::ErrorHandler do
  let(:dummy_class) do
    Class.new do
      include HttpLoader::Client::ErrorHandler

      attr_reader :logger

      def initialize(logger)
        @logger = logger
      end
    end
  end

  let(:logger) { instance_double(HttpLoader::Client::Logger, error: nil) }
  let(:instance) { dummy_class.new(logger) }

  describe '#handle_err' do
    it 'maps EMFILE intelligently cleanly natively' do
      instance.handle_err(0, Errno::EMFILE.new('dummy file'))
      expect(logger).to have_received(:error).with(/ERROR_EMFILE/)
    end

    it 'maps EADDRNOTAVAIL explicitly cleanly mapping safely' do
      instance.handle_err(1, Errno::EADDRNOTAVAIL.new('dummy addr'))
      expect(logger).to have_received(:error).with(/ERROR_EADDRNOTAVAIL/)
    end

    it 'falls back correctly explicitly to StandardError smoothly' do
      instance.handle_err(2, StandardError.new('custom msg'))
      expect(logger).to have_received(:error).with(/ERROR_OTHER: custom msg/)
    end
  end
end
