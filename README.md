# Fiber-Native High-Concurrency Load Testing Harness

An aggressively scalable asynchronous Ruby load testing harness built specifically to simulate, maintain, and monitor hundreds of thousands of active Keep-Alive connections seamlessly.
By circumventing traditional `1:1` OS Thread-per-connection blockers and utilizing Ruby 4.0+'s native `Fiber::Scheduler` bridging to modern native loopbacks (`kqueue`/`epoll`), this architecture handles mammoth concurrent loads autonomously on essentially `0.0%` CPU over just two hardware threads.

---

## Why & When to Use This Gem?

Traditional load testing tools (like `wrk`, Apache Bench, or Locust) are heavily optimized to maximize **Requests Per Second (RPS)** across short-lived HTTP connections. However, they struggle structurally when mathematically tasked with sustaining hundreds of thousands of *idle, continuous* connections simultaneously due to Thread context-switching overhead or memory limits.

**You need `keep_alive` when your principal bottleneck is concurrency, not throughput.**

### Core Use Cases:
1. **Testing Persistent Connections (SSE/WebSockets)**: Validating how gracefully your backend or infrastructure handles 100,000+ active users holding open Event Streams, WebSockets, or Long-Polling links without doing constant background work.
2. **Infrastructure Limitation Discovery**: Revealing hidden OS configuration ceilings before deployment, precisely finding edge drops such as File Descriptor starvation (`EMFILE`), Ephemeral Port exhaustion (`EADDRNOTAVAIL`), or reverse proxy RAM caps.
3. **Evaluating Cloud Load Balancers/Gateways**: Discovering the exact threshold where an AWS Application Load Balancer or Nginx edge autonomously decides to drop idle Keep-Alive mappings to release native memory.
4. **Resilience & Slowloris Simulation**: Ensuring your Thread-based infrastructure (e.g. Puma) correctly maps constraints and doesn't experience total thread-pool lockups when subjected to thousands of concurrent malicious stalled connections gracefully holding sockets hostage.

---

## Technical Dependencies

**Strict Requirements**
- **Ruby 4.0.2** (or strictly any Ruby 4.x environment that enforces native `Fiber::Scheduler` mechanics).
- **Core Gems**: `rack`, `rackup`, `falcon`, `async`, `async-http`

**Installation**
You can install the project globally as a gem which exposes the `keep_alive` executable:
```bash
gem install keep_alive
```
Or add it to your project via Bundler:
```bash
bundle add keep_alive
```

---

## Architecture Components

The architecture relies gracefully on three decoupled components mathematically synced through environment wrappers:

### 1. `keep_alive harness` (The Orchestrator)
The brain of the test. It parses constraints, artificially lifts File Descriptor caps (`setrlimit`), seamlessly manages process spawning, detects hardware bottlenecks in real-time, and aggressively reads Unix metrics (`ps`, `lsof`) translating them into a highly readable dashboard telemetry loop.

### 2. `keep_alive server` (The Local Endpoint)
Instead of relying on blocking thread platforms (like Puma), the local endpoint hosts `Rackup::Handler::Falcon`. It serves an infinite lightweight `Server-Sent Events` (SSE) heartbeat (`data: ping\n\n`) mapped strictly to the asynchronous reactor, rendering CPU overhead practically non-existent.

### 3. `keep_alive client` (The Asynchronous Initiator)
The client bypasses expensive `Thread.new` wrappers and deploys raw `Async` fiber blocks executing `Net::HTTP.start`. By utilizing `sleep`, the connections are specifically configured to never close from the client-side unless the target physically hangs up, guaranteeing true metric validation for idle Keep-Alive limits.

---

## Detailed Command-Line Parameters

You engage all functions purely through the `keep_alive` executable command interface.

**Syntax:**
`keep_alive harness [--connections_count=NUM] [FLAGS...]`

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `--connections_count=` | Integer | Optional | The total number of TCP sessions to spawn natively across the whole test. Defaults to 1000. (Must be >= 1). |
| `--https` | Flag | Optional | Configures TLS/SSL context. Forces internal targets to boot securely on `8443` and configures client payloads with `VERIFY_NONE`. |
| `--url=` | String | Optional | Triggers **External Target Mode** (e.g. `--url=https://site1.com,https://site2.com`). Harness bypasses local `keep_alive server` boot sequences completely to swarm remote targets via natively load-balanced round-robin. |
| `--verbose` | Flag | Optional | Enables extensive verbose logging dynamically mapping TCP `Connection established` and closures strictly into the Thread-safe `./logs/client.log` mutex. |
| `--[no-]ping` | Flag | Optional | Toggles Keep-Alive dynamic heartbeat pings off or on (default `true`). Sends an explicit `HEAD` request within the Keep-Alive tunnel routinely. |
| `--ping_period=` | Integer | Optional | Time in seconds strictly bounding how often Keep-Alive fiber pings aggressively repeat. Defaults to `5`. |
| `--keep_alive_timeout=` | Float | Optional | The strict mathematical upper-bound limit enforcing autonomous Client disconnects cleanly. Defaults to `0` (mathematically infinite). |
| `--bind_ips=` | String | Optional | Comma separated loopback or generic networking interfaces to sequentially map outgoing sockets against. (E.g. `127.0.0.1,127.0.0.2`). |
| `--proxy_pool=` | String | Optional | Comma separated proxy URIs (e.g. `http://proxy1:8080,http://user:pass@proxy2:8080`) to multiplex connections through. |
| `--headers=` | String | Optional | Comma separated `Key:Value` mapping of custom authorization or edge cache-bust headers injected strictly bypassing CDNs. |
| `--slowloris_delay=` | Float | Optional | Hijacks conventional HTTP handshakes writing raw single byte strings maliciously across mathematical delays designed natively to systematically lock thread-dependent Reverse Proxies cleanly. |
| `--export_json=` | String | Optional | Dumps the execution telemetry including `peak_connections` and mathematically evaluated OS FDs bottlenecks directly into a formatted JSON sink natively. |
| `--target_duration=` | Float | Optional | Enforces a hard runtime cap structurally across the `keep-alive` processes. The Harness mathematically halts explicitly once SECONDS is bypassed natively. |
| `--qps_per_connection=` | Integer | Optional | Upgrades pipelines to launch active rhythmic `GET` payloads natively per connected socket at RATE (Requires `--[no]-ping` bypassed). |
| `--connections_per_second=` | Integer | Optional | Native Fiber load rate-limiter dictating explicit TCP handshake delays natively avoiding `ddos`-style port clogs too early natively. Defaults to `0` (unlimited burst). |
| `--ramp_up=` | Float | Optional | Systematically scales the initial spawning rate uniformly over Seconds to evade trigger-based target scaling architectures like simple ASGs. Overrides static rates. |
| `--max_concurrent_connections=`| Integer | Optional | Configures strict `Async::Semaphore` caps mapping active concurrent sockets exactly natively. Defaults exactly to `--connections_count`. |
| `--reopen_closed_connections` | Flag | Optional | Maps organic resilience loops. TCP endpoints forcefully disrupted dynamically resurrect automatically via standard retry heuristics. |
| `--reopen_interval=` | Float | Optional | Forces absolute temporal `sleep()` gaps before restoring dropped target loops avoiding internal spin-lock CPU floods. Defaults to `5.0`. |
| `--read_timeout=` | Float | Optional | Directly hooks into native `Net::HTTP` parameters forcing standard request drop mechanics organically mapping. Defaults to `0` (unlimited). |
| `--user_agent=` | String | Optional | Overrides all HTTP payload identities statically natively evading specific rigid Bot detection infrastructures. Defaults to `Keep-Alive Test`. |
| `--jitter=` | Float | Optional | Adds a mathematical `±%` randomization (e.g., `0.2` for 20%) to all sleep intervals organically evading Thundering Herd bottlenecks. Defaults to `1.0`. |
| `--track_status_codes` | Flag | Optional | Synchronously intercepts Keeping-Alive Pings HTTP integer responses, safely logging HTTP `429` and `5xx` load balancer drops sequentially natively. |

---

## Execution Scenarios & Code Examples

### Scenario 1: Standard Plaintext Benchmarking
Benchmarks connection stability against the local application using plaintext packets. Perfect for finding file-descriptor limitations natively.
```bash
keep_alive harness --connections_count=150000
```
> Boots internal `keep_alive server` implicitly on HTTP strictly port `8080`.

### Scenario 2: Encryption Cost Calculation
Forces both local client/server infrastructure seamlessly into encrypted protocols using self-generated mathematical PKI contexts.
```bash
keep_alive harness --connections_count=1000 --https
```
> Boots internal `keep_alive server` natively on HTTPS securely executing over port `8443`.

### Scenario 3: External Endpoint Durability Testing
Testing a foreign server (e.g., Google Maps) to determine exactly what their Keep-Alive edge restrictions natively drop out at.
```bash
keep_alive harness --connections_count=5 --url="https://www.google.com/maps"
```
> Avoids booting `keep_alive server`. Metric Dashboard displays `"EXTERNAL"` for server metrics, while strictly tracking `Real Conns`. (Metrics show Google enforces a strict ~240-second (4 min) idle keep-alive retention hook before resetting TCP routes!).

### Scenario 4: Automated Orchestrator Scripts (Executors)
Instead of monitoring the terminal manually indefinitely, you can write Ruby wrapper scripts to trigger tests sequentially or track metrics completely autonomously.

#### Example A: Protocol Dual-Testing (HTTP -> HTTPS)
Executes a 5-second burst test across both local protocol frameworks back-to-back:
```ruby
require 'fileutils'
# test_protocols.rb

puts 'Starting HTTP burst...'
pid1 = spawn('keep_alive harness --connections_count=10', out: 'http.log', err: 'http.err')
sleep 5
Process.kill('INT', pid1)
Process.wait(pid1)

puts 'Starting HTTPS burst...'
pid2 = spawn('keep_alive harness --connections_count=10 --https', out: 'https.log', err: 'https.err')
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
pid = spawn("keep_alive harness --connections_count=5 --url='https://example.com'", out: 'monitor.log', err: 'monitor.err')
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

## 📊 Telemetry Metrics Explained

The `keep_alive harness` dashboard prints active, real-time measurements describing exactly how the client is scaling.

* **Time (UTC)**: Current absolute time in the UTC format for strict log matching.
* **Real Conns (Real Connections)**: This column strictly calculates the physical number of dynamically established network sockets originating from the active `client` loop.
  - **Linux Fast-Path**: Bypasses external tools entirely, natively parsing symlinks directly in `/proc/<PID>/fd/` and counting exclusively the descriptors returning exactly `socket:[*]`.
  - **macOS Fallback**: Since macOS lacks `/proc` socket references natively, it polls via `lsof -p <CLIENT_PID> -n -P` and mathematically counts the exact occurrences indicating the `ESTABLISHED` flag organically.
* **Srv/Cli CPU/Thrds**: Thread counts and combined relative CPU% measured across all threads dynamically allocated to each discrete process natively.
* **Srv/Cli Mem/Conn**: Provides immediate memory budgeting statistics organically derived by dividing total physical memory (RSS) by `Real Conns`.

---

## Hardware Limitations & Known Insights

This suite effortlessly scales through software. When you finally hit a plateau, the limitation exists natively within the Operating System.

### Limitations Observed During 150,000 Tests

**1. Ephemeral Port Starvation (`EADDRNOTAVAIL`)**
* **The Error:** `=> BOTTLENECK ACTIVE: [OS Ports Limit: 924 EADDRNOTAVAIL]`
* **The Insight:** A single networking loopback interface mapping `127.0.0.1` -> `127.0.0.1:8080` has a mathematically finite amount of dynamic connection identifiers. Standard macOS endpoints run out of ephemeral sockets at strictly ~`32,768` (or ~`16,384`) active connections depending on the kernel version.
* **The Reconnection Death-Spiral:** If your target Server hits its internal File Descriptor limits (for instance, dropping connections at exactly 5,000 sockets), and you run the test with `--reopen_closed_connections`, the Client will aggressively retry. This cycle will exhaust all 16k available ephemeral loopback ports within seconds by dumping them into `TIME_WAIT` lock, throwing `EADDRNOTAVAIL` artificially early.
* **The Solution:** To achieve 150k endpoints effectively sourced from a singular physical piece of hardware, you must dynamically generate multiple loopback addresses to expand your subnet ports implicitly:
```bash
sudo ifconfig lo0 alias 127.0.0.2 up
sudo ifconfig lo0 alias 127.0.0.3 up
```

**2. File Descriptor Limits (`EMFILE` & Server Rejections)**
* **The Error:** `=> BOTTLENECK ACTIVE: [OS FDs Limit: 40 EMFILE]` (Or silently dropped connections hovering exactly at `~5,000` to `~10,000`)
* **The Insight:** Operating systems heavily restrict total open file capabilities (sockets count as files natively). Standard macOS limits hardcap user file descriptors roughly near 5,000 or 10,000 (`kern.maxfilesperproc`). Once the Server hits this limit, it proactively rejects incoming sockets, which forces drops.
* **The Solution:** The harness tries to execute `Process.setrlimit` dynamically to add buffers. If blocked securely by native OS permissions or deep kernel limits, execute these configurations natively before the benchmark:
```bash
sudo sysctl -w kern.maxfiles=1000000
sudo sysctl -w kern.maxfilesperproc=1000000
ulimit -n 250000
```

**3. External Connection Timeouts (Keep-Alive Death)**
* **The Behavior:** When testing foreign servers (e.g., `--url=...`), external networking edges enforce strict limits on how long an idle HTTP TCP tunnel remains in `ESTABLISHED` mode.
* **The Insight:** Because the `keep_alive client` is engineered to `sleep` natively on $0.0\%$ CPU while holding the socket open, it will never close the connection locally. Instead, the upstream firewall organically terminates it.
* **The Automation:** The main `keep_alive harness` pipeline automatically calculates your peak connection limits. The exact moment the local OS recognizes the socket dropped natively (lapsing from `5` back down to `0`), the metric dashboard natively halts itself, intercepts the timeout organically, and reports exactly how long it survived directly to standard output:
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
