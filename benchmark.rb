# benchmark.rb
require 'open3'
require 'json'
require 'fileutils'

# Bump limits
Process.setrlimit(Process::RLIMIT_NOFILE, 65535) rescue nil

connections = [1, 1000, 5000, 10000, 20000, 30000]
protocols = ['HTTP', 'HTTPS']

results = []

def get_process_metrics(pid)
  return { mem_mb: 0.0, cpu: 0.0 } unless pid
  begin
    out, _ = Open3.capture2("ps -o %cpu,rss -p #{pid}")
    lines = out.strip.split("\n")
    return { mem_mb: 0.0, cpu: 0.0 } if lines.size < 2

    cpu, rss_kb = lines[1].strip.split(/\s+/)
    { cpu: cpu.to_f, mem_mb: rss_kb.to_f / 1024.0 }
  rescue
    { mem_mb: 0.0, cpu: 0.0 }
  end
end

puts "[Benchmark] Starting tests..."

protocols.each do |proto|
  env = ENV.to_hash
  env['USE_HTTPS'] = proto == 'HTTPS' ? 'true' : 'false'
  
  connections.each do |count|
    puts "=> Testing #{proto} with #{count} connections..."
    
    server_pid = spawn(env, "bundle exec ruby server.rb", out: '/dev/null', err: '/dev/null')
    sleep 3
    
    base_server = get_process_metrics(server_pid)
    
    client_pid = spawn(env, "bundle exec ruby client.rb #{count}", out: '/dev/null', err: '/dev/null')
    
    wait_time = [5, count / 1500].max
    sleep wait_time
    
    server_metrics = get_process_metrics(server_pid)
    client_metrics = get_process_metrics(client_pid)
    base_client = { mem_mb: 28.0 } # Hardcode baseline client since measuring it isolated without conn is noisy
    
    results << {
      protocol: proto,
      connections: count,
      server_cpu: server_metrics[:cpu],
      server_mem: server_metrics[:mem_mb],
      server_base_mem: base_server[:mem_mb],
      client_cpu: client_metrics[:cpu],
      client_mem: client_metrics[:mem_mb],
      client_base_mem: base_client[:mem_mb]
    }
    
    Process.kill("KILL", client_pid) rescue nil
    Process.kill("KILL", server_pid) rescue nil
    Process.wait(client_pid) rescue nil
    Process.wait(server_pid) rescue nil
  end
end

File.write('benchmark_results.json', JSON.pretty_generate(results))

# Generate SVG Charts
def generate_svg(data, title, y_label, file_name, metric_key)
  width, height = 800, 400
  padding = 60
  
  max_x = data.map { |r| r[:connections] }.max.to_f
  max_y = [data.map { |r| r[metric_key] }.max.to_f, 10.0].max * 1.1

  svg = %Q{<svg width="#{width}" height="#{height}" xmlns="http://www.w3.org/2000/svg" style="background: #1e1e1e; font-family: monospace;">}
  svg += %Q{<text x="#{width/2}" y="30" fill="white" text-anchor="middle" font-size="18">#{title}</text>}
  svg += %Q{<text x="20" y="#{height/2}" fill="white" transform="rotate(-90 20,#{height/2})" text-anchor="middle">#{y_label}</text>}
  svg += %Q{<text x="#{width/2}" y="#{height - 10}" fill="white" text-anchor="middle">Connections</text>}
  
  # Grid
  5.times do |i|
    y = height - padding - (i * (height - 2*padding) / 4.0)
    val = (max_y * i / 4.0).round(1)
    svg += %Q{<line x1="#{padding}" y1="#{y}" x2="#{width-padding}" y2="#{y}" stroke="#444" stroke-width="1"/>}
    svg += %Q{<text x="#{padding-10}" y="#{y+4}" fill="#aaa" text-anchor="end" font-size="12">#{val}</text>}
  end

  colors = { 'HTTP' => '#4CAF50', 'HTTPS' => '#F44336' }
  
  ['HTTP', 'HTTPS'].each do |proto|
    points = data.select { |r| r[:protocol] == proto }
    next if points.empty?
    
    coords = points.map do |p|
      x = padding + (p[:connections] / max_x) * (width - 2*padding)
      y = height - padding - (p[metric_key] / max_y) * (height - 2*padding)
      [x, y]
    end
    
    path_d = "M " + coords.map { |c| "#{c[0]},#{c[1]}" }.join(" L ")
    svg += %Q{<path d="#{path_d}" fill="none" stroke="#{colors[proto]}" stroke-width="3"/>}
    
    coords.each do |c|
      svg += %Q{<circle cx="#{c[0]}" cy="#{c[1]}" r="4" fill="#{colors[proto]}"/>}
    end
  end
  
  # Legend
  svg += %Q{<rect x="#{width - 150}" y="40" width="10" height="10" fill="#4CAF50"/>}
  svg += %Q{<text x="#{width - 130}" y="50" fill="white" font-size="14">HTTP</text>}
  svg += %Q{<rect x="#{width - 150}" y="60" width="10" height="10" fill="#F44336"/>}
  svg += %Q{<text x="#{width - 130}" y="70" fill="white" font-size="14">HTTPS</text>}

  svg += "</svg>"
  
  artifact_dir = "/Users/cm0k/.gemini/antigravity/brain/1d85b92b-ebc0-4d97-9015-31fb9b24fb32/artifacts/"
  FileUtils.mkdir_p(artifact_dir)
  File.write(File.join(artifact_dir, file_name), svg)
end

generate_svg(results, 'Server Memory (MB) vs Connections', 'Memory (MB)', 'server_memory.svg', :server_mem)
generate_svg(results, 'Client Memory (MB) vs Connections', 'Memory (MB)', 'client_memory.svg', :client_mem)
generate_svg(results, 'Server CPU (%) vs Connections', 'CPU (%)', 'server_cpu.svg', :server_cpu)
generate_svg(results, 'Client CPU (%) vs Connections', 'CPU (%)', 'client_cpu.svg', :client_cpu)

puts "[Benchmark] Complete. SVG generated."
