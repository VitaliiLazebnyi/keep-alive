# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe KeepAlive::Server do
  let(:server) { described_class.new }

  before do
    # Prevent stdout noise
    allow($stdout).to receive(:puts)
    allow(Rackup::Handler::Falcon).to receive(:run)
  end

  describe '#start' do
    context 'without https' do
      before { server.start(use_https: false, port: 8080) }

      it 'binds natively to plaintext HTTP', :rspec do
        expect(Rackup::Handler::Falcon)
          .to have_received(:run)
          .with(instance_of(Proc), Host: '0.0.0.0', Port: 8080)
      end
    end

    context 'with https' do
      let(:args) { { Host: '0.0.0.0', Port: 8443, SSLEnable: true, ssl_context: instance_of(OpenSSL::SSL::SSLContext) } }

      before { server.start(use_https: true, port: 8443) }

      it 'binds natively to HTTPS with generated keys', :rspec do
        expect(Rackup::Handler::Falcon)
          .to have_received(:run)
          .with(instance_of(Proc), hash_including(args))
      end
    end
  end

  describe 'app evaluator' do
    let(:response) { server.instance_variable_get(:@app).call({}) }

    it 'returns the correct status code', :rspec do
      expect(response[0]).to eq(200)
    end

    it 'returns the correct headers', :rspec do
      expect(response[1]['Content-Type']).to eq('text/event-stream')
    end

    it 'returns the correct body', :rspec do
      expect(response[2]).to be_a(Enumerator)
    end
  end
end
