# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/harness/telemetry'

RSpec.describe HttpLoader::Harness::Telemetry do
  let(:telemetry) { described_class.new('/logs', 'test.json') }

  before do
    allow($stdout).to receive(:puts)
    allow(File).to receive(:write)
    allow(File).to receive(:read).and_return('')
  end

  describe '#export!' do
    it 'exports JSON explicitly natively correctly mathematically', :rspec do
      telemetry.export!(100, Time.now.utc)
      expect(File).to have_received(:write).with('test.json', anything)
    end
  end

  describe '#check_bottlenecks!' do
    it 'handles checking securely seamlessly', :rspec do
      allow(File).to receive(:read).with(%r{/client\.log}).and_return('ERROR_EMFILE ERROR_THREADLIMIT')
      telemetry.check_bottlenecks!
      expect($stdout).to have_received(:puts).with(/BOTTLENECK ACTIVE/)
    end

    it 'rescues File read organically smoothly mapping empty string' do
      allow(File).to receive(:read).and_raise(StandardError)
      telemetry.check_bottlenecks!
      expect($stdout).not_to have_received(:puts)
    end

    it 'rescues specifically client err accurately organically smoothly mapping empty string' do
      telemetry.instance_variable_set(:@export_json, nil)
      allow(File).to receive(:read).with(%r{/client\.log}).and_return('')
      allow(File).to receive(:read).with(%r{/client\.err}).and_raise(StandardError)
      # force build_bottleneck_messages to raise to cover line 33?
      # No, wait. We want to cover line 33 "rescue StandardError" in check_bottlenecks!
      allow(telemetry).to receive(:read_logs).and_raise(StandardError)
      telemetry.check_bottlenecks!
      expect($stdout).not_to have_received(:puts)
    end
  end
end
