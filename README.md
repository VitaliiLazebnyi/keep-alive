# Fiber-Native High-Concurrency Load Testing Harness

An aggressively scalable asynchronous Ruby load testing harness built specifically to simulate, maintain, and monitor hundreds of thousands of active Keep-Alive connections seamlessly.
By circumventing traditional `1:1` OS Thread-per-connection blockers and utilizing Ruby 4.0+'s native `Fiber::Scheduler` bridging to modern native loopbacks (`kqueue`/`epoll`), this architecture handles mammoth concurrent loads autonomously on essentially `0.0%` CPU over just two hardware threads.

---

## Technical Dependencies

**Strict Requirements**
- **Ruby 4.0.2** (or strictly any Ruby 4.x environment that enforces native `Fiber::Scheduler` mechanics).
- **Core Gems**: `rack`, `rackup`, `falcon`, `async`, `async-http`

**Environment Initialization**
Ensure your dependencies match the ecosystem exactly using Bundler:
```bash
bundle install
```

---

## Architecture Components

The architecture relies gracefully on three decoupled components mathematically synced through environment wrappers:

### 1. `harness.rb` (The Orchestrator)
The brain of the test. It parses constraints, artificially lifts File Descriptor caps (`setrlimit`), seamlessly manages process spawning, detects hardware bottlenecks in real-time, and aggressively reads Unix metrics (`ps`, `lsof`) translating them into a highly readable dashboard telemetry loop.

### 2. `server.rb` (The Local Endpoint)
Instead of relying on blocking thread platforms (like Puma), the local endpoint hosts `Rackup::Handler::Falcon`. It serves an infinite lightweight `Server-Sent Events` (SSE) heartbeat (`data: ping\n\n`) mapped strictly to the asynchronous reactor, rendering CPU overhead practically non-existent.

### 3. `client.rb` (The Asynchronous Initiator)
The client bypasses expensive `Thread.new` wrappers and deploys raw `Async` fiber blocks executing `Net::HTTP.start`. By utilizing `sleep`, the connections are specifically configured to never close from the client-side unless the target physically hangs up, guaranteeing true metric validation for idle Keep-Alive limits.

---

## Detailed Command-Line Parameters

You engage all functions purely through the root `harness.rb` wrapper.

**Syntax:**
`ruby harness.rb [--connections_count=NUM] [FLAGS...]`

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `--connections_count=` | Integer | Optional | The exact number of concurrent TCP sessions/fibers you wish to spawn natively. Defaults to 1000. e.g., `--connections_count=100000` |
| `--https` | Flag | Optional | Configures TLS. Instructs `server.rb` to generate and enforce self-signed OpenSSL certificates over port `8443`, while overriding `client.rb` payloads securely with `verify_mode: OpenSSL::SSL::VERIFY_NONE`. |
| `--url=` | String | Optional | Triggers **External Target Mode**. Expects a full URI (e.g. `--url=http://example.com`). Harness will actively bypass loading the local server endpoint entirely out of the execution layer and pivot all local clients to swarm the remote address. |

---

## Execution Scenarios & Code Examples

### Scenario 1: Standard Plaintext Benchmarking
Benchmarks connection stability against the local application using plaintext packets. Perfect for finding file-descriptor limitations natively.
```bash
ruby harness.rb --connections_count=150000
```
> Boots internal `server.rb` implicitly on HTTP strictly port `8080`.

### Scenario 2: Encryption Cost Calculation
Forces both local client/server infrastructure seamlessly into encrypted protocols using self-generated mathematical PKI contexts.
```bash
ruby harness.rb --connections_count=1000 --https
```
> Boots internal `server.rb` natively on HTTPS securely executing over port `8443`.

### Scenario 3: External Endpoint Durability Testing
Testing a foreign server (e.g., Google Maps) to determine exactly what their Keep-Alive edge restrictions natively drop out at.
```bash
ruby harness.rb --connections_count=5 --url="https://www.google.com/maps"
```
> Avoids booting `server.rb`. Metric Dashboard displays `"EXTERNAL"` for server metrics, while strictly tracking `Real Conns`. (Metrics show Google enforces a strict ~240-second (4 min) idle keep-alive retention hook before resetting TCP routes!).

### Scenario 4: Automated Orchestrator Scripts (Executors)
Instead of monitoring the terminal manually indefinitely, you can write Ruby wrapper scripts to trigger tests sequentially or track metrics completely autonomously.

#### Example A: Protocol Dual-Testing (HTTP -> HTTPS)
Executes a 5-second burst test across both local protocol frameworks back-to-back:
```ruby
require 'fileutils'
# test_protocols.rb

puts 'Starting HTTP burst...'
pid1 = spawn('ruby harness.rb --connections_count=10', out: 'http.log', err: 'http.err')
sleep 5
Process.kill('INT', pid1)
Process.wait(pid1)

puts 'Starting HTTPS burst...'
pid2 = spawn('ruby harness.rb --connections_count=10 --https', out: 'https.log', err: 'https.err')
sleep 5
Process.kill('INT', pid2)
Process.wait(pid2)
```

#### Example B: External Durability Tracking
Spawns an external target and tracks how many strict seconds the target holds the socket before forcefully killing it:
```ruby
require 'fileutils'
# test_endurance.rb

start_time = Time.now
pid = spawn("ruby harness.rb --connections_count=5 --url='https://example.com'", out: 'monitor.log', err: 'monitor.err')
sleep 10 # Wait for native initialization

loop do
  # Read the active output safely
  lines = begin
    File.read('monitor.log')
  rescue StandardError
    ''
  end.split("\n").grep(/^\d{2}:\d{2}:\d{2}/)
  if lines.any? && lines.last.split('|')[1].to_i.zero?
    puts "Server disconnected actively after #{(Time.now - start_time).round(2)} seconds."
    break
  end
  sleep 4
end

Process.kill('INT', pid)
```

---

## Hardware Limitations & Known Insights

This suite effortlessly scales through software. When you finally hit a plateau, the limitation exists natively within the Operating System.

### Limitations Observed During 150,000 Tests

**1. Ephemeral Port Starvation (`EADDRNOTAVAIL`)**
* **The Error:** `=> BOTTLENECK ACTIVE: [OS Ports Limit: 924 EADDRNOTAVAIL]`
* **The Insight:** A single networking loopback interface mapping `127.0.0.1` -> `127.0.0.1:8080` has a mathematically finite amount of dynamic connection identifiers. Standard macOS endpoints run out of ephemeral sockets at strictly ~`32,768` active connections. The codebase will flawlessly survive this starvation remaining at `0.0% CPU`, aggressively logging it cleanly without crashing.
* **The Solution:** To achieve 150k endpoints effectively sourced from a singular physical piece of hardware, you must dynamically generate multiple loopback addresses to expand your subnet ports implicitly:
```bash
sudo ifconfig lo0 alias 127.0.0.2 up
sudo ifconfig lo0 alias 127.0.0.3 up
```

**2. File Descriptor Limits (`EMFILE`)**
* **The Error:** `=> BOTTLENECK ACTIVE: [OS FDs Limit: 40 EMFILE]`
* **The Insight:** Operating systems heavily restrict total open file capabilities (sockets count as files natively).
* **The Solution:** The harness tries to execute `Process.setrlimit` dynamically to add buffers. If blocked securely by native OS permissions, execute root privileges proactively:
```bash
ulimit -n 250000
```

**3. External Connection Timeouts (Keep-Alive Death)**
* **The Behavior:** When testing foreign servers (e.g., `--url=...`), external networking edges enforce strict limits on how long an idle HTTP TCP tunnel remains in `ESTABLISHED` mode.
* **The Insight:** Because `client.rb` is engineered to `sleep` natively on $0.0\%$ CPU while holding the socket open, it will never close the connection locally. Instead, the upstream firewall organically terminates it.
* **The Automation:** The main `harness.rb` pipeline automatically calculates your peak connection limits. The exact moment the local OS recognizes the socket dropped natively (lapsing from `5` back down to `0`), the metric dashboard natively halts itself, intercepts the timeout organically, and reports exactly how long it survived directly to standard output:
```text
[Harness] ⚠️ EXTERNAL SERVER DISCONNECTED! All TCP Keep-Alive sockets were forcefully dropped.
[Harness] The endpoints natively survived for mathematically 242.25 seconds.
```

### Encryption Memory Economics
While CPU/Threading metrics hovered essentially permanently around `0.0%` over `2 Threads`, tracking RAM natively produced incredibly useful deployment thresholds:

* **HTTP Constraints:** At rest natively, Client overhead averaged `~72.4 KB` per connection. Server overhead was roughly `~113.6 KB` per persistent heartbeat.
* **HTTPS Overhead:** Introducing block ciphers and OpenSSL buffers exponentially explodes user RAM requirements payload. Handshakes natively forced the Client metrics out to `~166.3 KB` natively per socket, increasing overhead practically by **`2.3x`**.

To securely hold 100,000 active HTTPS tunnels open smoothly utilizing this architecture, the host machine simply requires around `~18GB` to `~20GB` of available physical memory explicitly.

---

## 🔍 Network Diagnostics & Local Telemetry

When tracking aggressive keep-alive behavior, native macOS/Linux Unix telemetry tools are required to ensure connections are actually held in memory and the OS isn't silently closing endpoints.

### 1. Diagnosing Local Ports & Connection Status
To view if your benchmark endpoints are genuinely active, use `lsof` (List Open Files) bounded strictly to our local test ports:
```bash
# Check if Falcon successfully bound to network edges:
lsof -i :8080 -sTCP:LISTEN
# View all established connections originating natively against the local server:
lsof -iTCP -sTCP:ESTABLISHED | grep ruby
```

### 2. Checking Ephemeral Port Busyness (TIME_WAIT Exhaustion)
As seen in extremely fast harness loops, macOS frequently traps abruptly killed sockets in `TIME_WAIT` to catch trailing packets. You can trace this exhaustion organically utilizing `netstat`:
```bash
# Get strict mathematical counts of all heavily exhausted Keep-Alive sockets on your machine natively:
netstat -an | grep TIME_WAIT | wc -l

# View precisely which tests are locking loopback ports:
netstat -anpf inet | grep 8080
```

### 3. Monitoring Raw Connection Traffic
To observe underlying physical TCP/IP byte transfer rates and verify traffic flow explicitly, utilize the `nettop` (macOS native) or `ss` utilities:
```bash
# macOS native active interface inspector:
nettop -m tcp -J state,bytes_in,bytes_out

# Standard Linux Socket Statistics (SS) alternative:
ss -tulpen | grep 8080
```

### 4. Intercepting Payload Data (Packet Sniffing)
Because `rack/falcon` streams live TCP SSE lines across the loopback unencrypted (over HTTP on 8080), you can aggressively sniff and intercept the individual `PING/PONG` traffic payloads completely undetected at the kernel layer using `tcpdump`.
```bash
# Sniff strict ASCII payload headers and body bounds passing over local interface 0 mapping perfectly to the benchmark port:
sudo tcpdump -i lo0 port 8080 -A
```

*Note: You cannot intercept HTTPS (port `8443`) natively with `tcpdump` because it leverages block-cipher encryption. To inspect TLS loads, you would need to proxy the Ruby client bindings organically through a platform like `mitmproxy` and natively dump the Root CA into your macOS keychain.*
