# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'http_loader/client/logger'

RSpec.describe HttpLoader::Client::Logger do
  require 'tmpdir'

  let(:logger) { described_class.new(true) }
  let(:tmp_dir) { Dir.mktmpdir }

  before do
    logger.instance_variable_set(:@log_dir, tmp_dir)
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  describe '#setup_files!' do
    it 'creates directories and files deterministically natively', :rspec do
      logger.setup_files!
      expect(File.exist?(File.join(tmp_dir, 'client.log'))).to be(true)
      expect(File.exist?(File.join(tmp_dir, 'client.err'))).to be(true)
    end
  end

  describe '#info' do
    it 'pushes into log queue successfully', :rspec do
      logger.info('test')
      expect(logger.instance_variable_get(:@log_queue).size).to eq(1)
    end
  end

  describe '#error' do
    it 'pushes exclusively into error queue successfully', :rspec do
      logger.error('failed')
      expect(logger.instance_variable_get(:@log_queue).pop).to include(:error)
    end
  end

  describe 'Queue management' do
    before do
      logger.setup_files!
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'flushes synchronously safely tracking both queues' do
      logger.info('test info')
      logger.error('test err')
      logger.flush_synchronously!

      expect(File.read(File.join(tmp_dir, 'client.log'))).to match(/test info/)
      expect(File.read(File.join(tmp_dir, 'client.err'))).to match(/test err/)
    end

    it 'rescues StandardError securely gracefully during synchronous flush' do
      allow(File).to receive(:open).and_raise(StandardError)
      expect { logger.flush_synchronously! }.not_to raise_error
    end

    it 'runs highly reliably through fetch looping cleanly' do
      logger.info('i1')
      logger.instance_variable_get(:@log_queue) << :terminate

      task = instance_double(Async::Task, async: nil, sleep: nil)
      allow(task).to receive(:async).and_yield
      logger.run_task(task)

      expect(File.read(File.join(tmp_dir, 'client.log'))).to match(/i1/)
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'skips logging if fetch message returns nil naturally' do
      logger.instance_variable_get(:@log_queue) << :terminate
      task = instance_double(Async::Task, async: nil, sleep: nil)
      allow(logger).to receive(:fetch_message).and_return(nil, :terminate)

      allow(task).to receive(:async).and_yield
      logger.run_task(task)

      expect(File.read(File.join(tmp_dir, 'client.log'))).to eq('')
    end

    # -- Architectural Note: RSpec integrations logically require lengthy isolated mock state bindings.
    it 'sleeps elegantly securely when ThreadError evaluates securely' do
      task = instance_double(Async::Task, async: nil, sleep: nil)
      allow(logger.instance_variable_get(:@log_queue)).to receive(:pop).and_raise(ThreadError)
      expect(logger.send(:fetch_message, task)).to be_nil
      expect(task).to have_received(:sleep).with(0.05)
    end
  end
end
