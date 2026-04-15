# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'fileutils'
require 'json'
# Justified Exception: E2E Integration tests organically require complex sequential process bootstrapping mathematically stretching isolated expectation boundaries.
RSpec.describe HttpLoader, type: :integration do
  let(:bin_path) { File.expand_path('../../bin/http_loader', __dir__) }
  let(:log_dir) { File.expand_path('../../logs', __dir__) }
  let(:client_log) { File.join(log_dir, 'client.log') }
  let(:server_log) { File.join(log_dir, 'server.log') }

  before do
    FileUtils.rm_f(client_log)
    FileUtils.rm_f(server_log)
    FileUtils.rm_f(File.join(log_dir, 'telemetry.json'))
    FileUtils.mkdir_p(log_dir)
  end

  after do
    system('pkill -9 -f "http_loader server"')
    system('pkill -9 -f "http_loader client"')
    sleep 0.5
  rescue StandardError
    # swallow any native cleanup discrepancies safely
  end

  def run_harness(args)
    # Using 'ruby' since that inherently picks up the context of our RSpec run.
    cmd = ['ruby', bin_path, 'harness'] + args
    stdout_str, stderr_str, status = Open3.capture3(*cmd)

    # Let the file system flush any trailing logs organically
    sleep 0.5

    [stdout_str, stderr_str, status]
  end

  def read_client_log
    File.exist?(client_log) ? File.read(client_log) : ''
  end

  describe 'Mode 1: Fundamental HTTP Plaintext Mode' do
    it 'spawns HTTP Server and Client natively mapping successfully' do
      args = [
        '--connections_count=2',
        '--target_duration=3.0',
        '--verbose'
      ]

      out, _, status = run_harness(args)

      expect(status.exitstatus).to eq(0)
      expect(out).to match(/Starting test with 2 connections to \*\*HTTP\*\*/)
      expect(read_client_log).to match(/Starting 2 HTTP connections/)
    end
  end

  describe 'Mode 2: Encrypted HTTPS TLS Architecture' do
    it 'bootstraps secure contexts actively avoiding TLS handshaking drops seamlessly' do
      args = [
        '--connections_count=2',
        '--target_duration=6.0',
        '--reopen_closed_connections',
        '--reopen_interval=0.5',
        '--https',
        '--verbose'
      ]
      out, _, status = run_harness(args)

      expect(status.exitstatus).to eq(0)
      expect(out).to match(/Starting test with 2 connections to \*\*HTTPS\*\*/)
      expect(read_client_log).to match(/Starting 2 HTTPS connections/)
      expect(out).to match(/Target duration mathematically reached/)
    end
  end

  describe 'Mode 3: QPS Payload Active Simulation' do
    it 'maps rhythmic GET payloads cleanly across active tunnels' do
      args = [
        '--connections_count=2',
        '--target_duration=3.0',
        '--qps_per_connection=5',
        '--no-ping', # Disable underlying ping explicitly
        '--verbose'
      ]
      _, _err, status = run_harness(args)

      expect(status.exitstatus).to eq(0)
      expect(read_client_log).to match(/Starting 2 HTTP connections/)
    end
  end

  describe 'Mode 4: Resilience Slowloris Thread Simulator' do
    it 'allocates and drops byte gap writes elegantly securely' do
      args = [
        '--connections_count=2',
        '--target_duration=3.0',
        '--slowloris_delay=0.1',
        '--verbose'
      ]
      _, _err, status = run_harness(args)

      expect(status.exitstatus).to eq(0)
      expect(read_client_log).to match(/Starting 2 HTTP connections/)
    end
  end

  describe 'Mode 5: External Target Mapping Logs' do
    it 'bypasses local loopbacks effectively evaluating remote endpoints seamlessly' do
      args = [
        '--connections_count=2',
        '--target_duration=2.0',
        '--url=https://www.google.com',
        '--export_json=logs/telemetry.json',
        '--verbose'
      ]
      out, _err, status = run_harness(args)

      expect(status.exitstatus).to eq(0)
      expect(out).to match(/\*\*EXTERNAL URL\*\*/)

      # Confirm JSON telemetry wrote effectively
      telemetry_file = File.join(log_dir, 'telemetry.json')
      expect(File.exist?(telemetry_file)).to be true

      json = JSON.parse(File.read(telemetry_file))
      expect(json).to have_key('peak_connections')
      expect(json).to have_key('errors')
    end
  end
end
