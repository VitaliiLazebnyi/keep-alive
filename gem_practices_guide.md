# Ruby Gem Development Practices & Configuration Guide

This document captures the best practices, architectural approaches, and configurations utilized in modern, high-quality Ruby gems (such as `http_loader`). It serves as a blueprint for AI agents and developers building resilient, well-tested, securely-released, and strictly-typed Ruby gems.

## 1. Static Type Checking with Sorbet

The project leverages [Sorbet](https://sorbet.org/) for robust, static type checking.

- **Dependencies**: Includes `sorbet-runtime` as a runtime dependency and `sorbet` / `yard-sorbet` as development dependencies.
- **Static Configuration**: The `sorbet/config` file is used to aggressively ignore irrelevant paths (`vendor/`, `coverage/`, `doc/`, `spec/`, etc.) to improve scanning performance.
- **Strictness**: Code files are expected to utilize `# typed: strong` or `# typed: strict` inline pragmas to ensure comprehensive type safety.
- **Runtime Testing Exclusions**: Within `spec/spec_helper.rb`, the runtime type error listeners are stubbed out during RSpec execution:
  ```ruby
  require 'sorbet-runtime'
  T::Configuration.inline_type_error_handler = ->(_, _) {}
  T::Configuration.call_validation_error_handler = ->(_, _) {}
  ```
  This guarantees that negative tests asserting behavior with invalid attributes don't crash from Sorbet runtime validations.

## 2. Code Quality & Linting (RuboCop)

The codebase implements strict coding standards through RuboCop, leveraging several specialized plugins beyond the default rule set.

- **Applied Plugins**: 
  - `rubocop-performance`
  - `rubocop-thread_safety` (imperative for async/threaded workloads)
  - `rubocop-rake`, `rubocop-rspec`, `rubocop-md` (Markdown linting).
- **Custom Local Cops**: The configuration allows for custom, domain-specific AI cops defined in the project:
  ```yaml
  require:
    - ./lib/rubocop/cop/ai/adverb_spam.rb
  AI/AdverbSpam:
    Enabled: true
  ```
- **Constraints enforced**:
  - `Style/FrozenStringLiteralComment: Enabled: true` (for memory footprint optimization).
  - Target Ruby execution contexts are explicitly defined.
  - **No Inline Exceptions**: The codebase strictly forbids the use of inline RuboCop disable directives (e.g., `# rubocop:disable All`). RuboCop offenses must be actively resolved via architectural refactoring rather than silenced.

## 3. RSpec Testing Suite

1. **RSpec Configuration** (`.rspec`):
   - Execution is randomized (`--order random`) to expose state bleed between tests.
   - Profiling is enabled (`--profile 10`) to identify the top 10 slowest executing tests continuously.
2. **Coverage mandates (SimpleCov)**:
   - Initialized in `spec_helper.rb`, setting `enable_coverage :branch` mapping all tested code.
   - **Strict 100% Coverage**: 100% logic and branch test coverage is rigorously mandated. 
   - **No Exemptions**: The codebase strictly forbids the use of coverage-dodging exception directives (e.g., `# rubocop:disable`, `# type: ignore`, `# pragma: no cover`) to artificially inflate coverage metrics. All tests must verify real state changes.
3. **Mocks and Expectations**:
   - `verify_partial_doubles = true` ensures that when mocking an object, it accurately implements the original object's signature preventing "mock drift".

## 4. Documentation (YARD)

YARD heavily drives code discoverability and API usability.

- **Configuration** (`.yardopts`):
  - Configures the output format as markdown (`--markup markdown`).
  - Instructs YARD to utilize the `sorbet` plugin (`--plugin sorbet`) so Sorbet signatures are automatically ingested into documentation metadata.
- **Enforcement**:
  - Utilizing `yard stats --list-undoc` inside GitHub CI workflows ensures the release blocks if any public class, module, or method lacks inline documentation.

## 5. Security: Gem Code Signing and Certificates

Cryptographic signing ensures end-to-end security and integrity verification of the published `.gem` artifacts.

- Inside the `http_loader.gemspec`:
  ```ruby
  spec.cert_chain  = ['certs/http_loader-public_cert.pem']
  spec.signing_key = File.expand_path('~/.gem/gem-private_key.pem') if $PROGRAM_NAME.end_with?('gem') && File.exist?(File.expand_path('~/.gem/gem-private_key.pem'))
  ```
- The public certificate is distributed with the repository. 
- The private key is securely stored in CI secrets and dynamically evaluated. It prevents the local `gem build` from failing for developers who do not possess the private key.

## 6. Continuous Integration & Delivery (GitHub Actions)

### CI Verification Pipeline (`ci.yml`)
The workflow operates on every push/PR against a matrix. Steps execute sequentially blocking failures:
1. **Modern Action Tools**: Always utilize up-to-date, pinned major versions for core actions (e.g., `actions/checkout@v6`, `ruby/setup-ruby@v1`).
2. **Fast Dependency Tracking**: Setup Ruby and aggressively cache dependencies natively via `bundler-cache: true`.
3. **Linting**: `bundle exec rubocop`
4. **Testing**: `bundle exec rspec`
5. **Typing**: `bundle exec srb tc --typed strong`
6. **Documentation**: Build YARD and run `yard stats --list-undoc`
7. **Integrity checks**: Validating gem builds locally (`gem build`).

### Automated Secure Releases (`release.yml`) 
Initiated upon semantic version tagging (`v*.*.*`):
1. **Version synchronisation**: Dynamically replaces the static version string in `lib/.../version.rb` mapped directly from the git tag.
2. **Key Inject**: Reconstructs `gem-private_key.pem` through GitHub Secrets to sign the release.
3. **Release deployment**: Pushes to GitHub Releases (creating assets like `.gem`).
4. **Registry Push**: Distributes directly to `--push_host` RubyGems securely via GitHub OIDC publishing actions, circumventing standard OTP complications.

## 7. Reliability & Architecture Guidelines (Best Practices)

To make a Ruby project strictly resilient and reliable:
1. **Segregation of Intent**:
   - Dedicate `REQUIREMENTS.md` representing current active specifications uniquely tagged (e.g., `CORE-REQ-001`).
   - Catalog defects explicitly in `BUGS.md` decoupled from standard development tasks.
2. **Immutability First**: Default to `# frozen_string_literal: true`. Never map values loosely.
3. **Fail-Fast Error Handling**: Throw explicit custom library exceptions inside domain boundaries rather than propagating StandardError out un-handled.
4. **Hermetic Testing**: Utilize clock freezes, deterministic PRNGs, and exact mock borders. Never execute network commands in RSpec suites.
5. **Absolute Thread Safety**: When writing multi-concurrency code in Ruby, utilize `Mutex` heavily, avoid mutating class-level/global state variables, and leverage `rubocop-thread_safety` analyzers strictly.

## 8. Environment & Dependency Management

Establishing reproducible development environments relies on explicitly defined configurations:

1. **Ruby Versioning**: Track the exact Ruby version using a `.ruby-version` file to ensure parity between developer machines and CI contexts. Modern toolchains (like `mise` or `rbenv`) naturally ingest this.
2. **Dependency Pinning (Gemspec vs. Gemfile)**:
   - For execution contexts and CI runs, strictly commit and lock versions via `Gemfile.lock`.
   - For standard gem distribution, specify safe version bounds utilizing the pessimistic operator (`~>`) inside the `gemspec`. Do not aggressively over-constrain the gem's dependencies.
3. **Environment Determinism**: Enforce locale semantics explicitly (e.g., establishing `ENV['LANG'] = ENV.fetch('LANG', 'en_US.UTF-8')` statically in Rakefiles or CI configurations) to avert subtle encoding failures across distributed platforms.
