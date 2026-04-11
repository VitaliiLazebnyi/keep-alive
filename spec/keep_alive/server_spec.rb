# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe KeepAlive::Server do
  let(:server) { described_class.new }

  before do
    # Prevent stdout noise
    allow($stdout).to receive(:puts)
    allow(Rackup::Handler::Falcon).to receive(:run)
    allow(IO::Endpoint).to receive(:tcp).and_return(double('tcp_endpoint'))
    allow(IO::Endpoint::SSLEndpoint).to receive(:new).and_return(double('ssl_endpoint'))
    allow(Protocol::Rack::Adapter).to receive(:new).and_return(double('adapter'))
    mock_falcon = double('falcon')
    allow(mock_falcon).to receive(:run).and_return(double('server_task', wait: true))
    allow(Falcon::Server).to receive(:new).and_return(mock_falcon)
  end

  describe '#start' do
    context 'without https' do
      it 'binds natively to plaintext HTTP', :rspec do
        server.start(use_https: false, port: 8080)
        expect(Rackup::Handler::Falcon)
          .to have_received(:run)
          .with(instance_of(Proc), Host: '0.0.0.0', Port: 8080)
      end

      it 'traps INT signal cleanly over generic Rackup layer', :rspec do
        allow(Rackup::Handler::Falcon).to receive(:run).and_yield(double('mock_server'))
        allow(server).to receive(:trap).with('INT').and_yield
        allow(server).to receive(:exit)
        expect { server.start(use_https: false, port: 8080) }.to output(/Shutting down immediately/).to_stdout
      end
    end

    context 'with https' do
      it 'binds natively to HTTPS with generated keys', :rspec do
        server.start(use_https: true, port: 8443)
        expect(Falcon::Server).to have_received(:new)
      end

      it 'traps INT signal securely alongside active SSLEndpoints natively', :rspec do
        allow(server).to receive(:trap).with('INT').and_yield
        allow(server).to receive(:exit)
        task_mock = double('mock_task', stop: nil)
        allow(server).to receive(:Sync).and_yield(task_mock)
        expect { server.start(use_https: true, port: 8443) }.to output(/Shutting down immediately/).to_stdout
      end
    end
  end

  describe 'app evaluator' do
    let(:response) { server.instance_variable_get(:@app).call({}) }

    it 'returns the correct status code', :rspec do
      expect(response[0]).to eq(200)
    end

    it 'returns the correct headers', :rspec do
      expect(response[1]['Content-Type']).to eq('text/plain')
    end

    it 'returns the correct body', :rspec do
      expect(response[2]).to eq(['OK'])
    end
  end
end
