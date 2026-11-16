# Dependency inventory — P1.1b

Snapshot: 2026-11-15. Before: commit `96024b9`, Ruby 3.3.5; after: Ruby 3.4.12. Stable RubyGems releases only. Installed-before lists versions present in that Ruby installation; the lockfile determines what the application uses. Native platform variants are collapsed by name/version. Every selected after-version was installed locally. Bundler is included as a toolchain row from BUNDLED WITH; RubyGems additionally moves 3.6.9 → 4.1.0.

`Compatible before` is the version reported by `bundle outdated --strict --parseable` under the original Gemfile, or the locked version if absent. `Latest stable` is the unconstrained outdated report; actual selection additionally respects Ruby/platform and transitive requirements. No compatible updates remain in the final graph. Two unconstrained updates are blocked by upstream requirements: RSpec requires diff-lcs <2 and Active Storage requires Marcel ~>1.0.

| Gem | Before role / constraint | Locked before | Installed before | Compatible before | Latest stable | Selected after |
| --- | --- | --- | --- | --- | --- | --- |
| action_text-trix | transitive | 2.1.16 | 2.1.16 | 2.1.19 | 2.1.19 | 2.1.19 |
| actioncable | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| actionmailbox | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| actionmailer | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| actionpack | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| actiontext | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| actionview | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| activejob | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| activemodel | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| activerecord | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| activestorage | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| activesupport | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| addressable | transitive | 2.8.8 | 2.8.8 | 2.9.2 | 2.9.2 | 2.9.2 |
| airbrussh | transitive | 1.6.2 | 1.6.2 | 1.6.2 | 1.6.2 | 1.6.2 |
| ast | transitive | 2.4.3 | 2.4.3 | 2.4.3 | 2.4.3 | 2.4.3 |
| base64 | transitive | 0.3.0 | 0.2.0, 0.3.0 | 0.3.0 | 0.3.0 | 0.3.0 |
| bcrypt | direct: `~> 3.1` | 3.1.22 | 3.1.22 | 3.1.22 | 3.1.22 | 3.1.22 |
| bcrypt_pbkdf | transitive | 1.1.2 | 1.1.2 | 1.1.2 | 1.1.2 | 1.1.2 |
| bigdecimal | transitive | 4.0.1 | 3.1.5, 4.0.1 | 4.1.3 | 4.1.3 | 4.1.3 |
| bindex | transitive | 0.8.1 | 0.8.1 | 0.8.1 | 0.8.1 | 0.8.1 |
| bootsnap | direct: `>= 0` | 1.21.1 | 1.21.1 | 1.26.1 | 1.26.1 | 1.26.1 |
| brakeman | direct: `>= 0` | 8.0.1 | 8.0.1 | 8.1.0 | 8.1.0 | 8.1.0 |
| builder | transitive | 3.3.0 | 3.3.0 | 3.3.0 | 3.3.0 | 3.3.0 |
| bundler | toolchain | 4.0.3 | 4.0.3 | 4.1.0 | 4.1.0 | 4.1.0 |
| bundler-audit | direct: `>= 0` | 0.9.3 | 0.9.3 | 0.9.3 | 0.9.3 | 0.9.3 |
| capistrano | direct: `~> 3.19` | 3.20.1 | 3.20.1 | 3.20.1 | 3.20.1 | 3.20.1 |
| capistrano-bundler | transitive | 2.2.0 | 2.2.0 | 2.2.0 | 2.2.0 | 2.2.0 |
| capistrano-rails | direct: `>= 0` | 1.7.0 | 1.7.0 | 1.7.0 | 1.7.0 | 1.7.0 |
| capybara | direct: `>= 0` | 3.40.0 | 3.40.0 | 3.40.0 | 3.40.0 | 3.40.0 |
| coderay | transitive | 1.1.3 | 1.1.3 | 1.1.3 | 1.1.3 | 1.1.3 |
| concurrent-ruby | transitive | 1.3.6 | 1.3.6 | 1.3.8 | 1.3.8 | 1.3.8 |
| connection_pool | transitive | 3.0.2 | 3.0.2 | 3.0.2 | 3.0.2 | 3.0.2 |
| crack | transitive | 1.0.1 | 1.0.1 | 1.0.1 | 1.0.1 | 1.0.1 |
| crass | transitive | 1.0.6 | 1.0.6 | 1.0.8 | 1.0.8 | 1.0.8 |
| date | transitive | 3.5.1 | 3.3.4, 3.5.1 | 3.6.0 | 3.6.0 | 3.6.0 |
| debug | direct: `>= 0` | 1.11.1 | 1.11.1, 1.9.1 | 1.11.1 | 1.11.1 | 1.11.1 |
| diff-lcs | transitive | 1.6.2 | 1.6.2 | 1.6.2 | 2.0.0 | 1.6.2 |
| domain_name | transitive | 0.6.20240107 | 0.6.20240107 | 0.7.20261031 | 0.7.20261031 | 0.7.20261031 |
| dotenv | transitive | 3.2.0 | 3.2.0 | 3.2.0 | 3.2.0 | 3.2.0 |
| dotenv-rails | direct: `>= 0` | 3.2.0 | 3.2.0 | 3.2.0 | 3.2.0 | 3.2.0 |
| drb | transitive | 2.2.3 | 2.2.0, 2.2.3 | 2.2.3 | 2.2.3 | 2.2.3 |
| ed25519 | transitive | 1.4.0 | 1.4.0 | 1.4.0 | 1.4.0 | removed |
| erb | transitive | 6.0.1 | 4.0.3, 6.0.1 | 6.0.7 | 6.0.7 | 6.0.7 |
| erubi | transitive | 1.13.1 | 1.13.1 | 1.13.1 | 1.13.1 | 1.13.1 |
| et-orbi | transitive | 1.4.0 | 1.4.0 | 1.4.2 | 1.4.2 | 1.4.2 |
| ffi | transitive | 1.17.3 | 1.17.3 | 1.17.4 | 1.17.4 | 1.17.4 |
| ffi-compiler | transitive | 1.3.2 | 1.3.2 | 1.4.3 | 1.4.3 | removed |
| fugit | transitive | 1.12.1 | 1.12.1 | 1.14.0 | 1.14.0 | 1.14.0 |
| globalid | transitive | 1.3.0 | 1.3.0 | 1.4.0 | 1.4.0 | 1.4.0 |
| hashdiff | transitive | 1.2.1 | 1.2.1 | 1.2.2 | 1.2.2 | 1.2.2 |
| http | direct: `~> 5.0` | 5.3.1 | 5.3.1 | 5.3.1 | 6.0.4 | 6.0.4 |
| http-cookie | transitive | 1.1.0 | 1.1.0 | 1.1.6 | 1.1.6 | 1.1.6 |
| http-form_data | transitive | 2.3.0 | 2.3.0 | 2.3.0 | 3.0.1 | removed |
| i18n | transitive | 1.14.8 | 1.14.8 | 1.15.2 | 1.15.2 | 1.15.2 |
| image_processing | direct: `~> 1.2` | 1.14.0 | 1.14.0 | 1.14.0 | 2.2.0 | 2.2.0 |
| importmap-rails | direct: `>= 0` | 2.2.3 | 2.2.3 | 2.2.3 | 2.2.3 | 2.2.3 |
| io-console | transitive | 0.8.2 | 0.7.1, 0.8.2 | 0.9.5 | 0.9.5 | 0.9.5 |
| irb | transitive | 1.16.0 | 1.13.1, 1.16.0 | 1.19.0 | 1.19.0 | 1.19.0 |
| json | transitive | 2.18.0 | 2.18.0, 2.7.1 | 3.1.0 | 3.1.0 | 3.1.0 |
| kamal | direct: `>= 0` | 2.10.1 | 2.10.1 | 2.12.0 | 2.12.0 | removed |
| language_server-protocol | transitive | 3.17.0.5 | 3.17.0.5 | 3.17.0.6 | 3.17.0.6 | 3.17.0.6 |
| lint_roller | transitive | 1.1.0 | 1.1.0 | 1.1.0 | 1.1.0 | 1.1.0 |
| llhttp | new | — | — | — | 0.6.2 | 0.6.2 |
| llhttp-ffi | transitive | 0.5.1 | 0.5.1 | 0.5.1 | 0.5.1 | removed |
| logger | transitive | 1.7.0 | 1.6.0, 1.7.0 | 1.7.0 | 1.7.0 | 1.7.0 |
| loofah | transitive | 2.25.0 | 2.25.0 | 2.25.3 | 2.25.3 | 2.25.3 |
| mail | transitive | 2.9.0 | 2.9.0 | 2.9.1 | 2.9.1 | 2.9.1 |
| marcel | transitive | 1.1.0 | 1.1.0 | 1.2.1 | 2.1.0 | 1.2.1 |
| matrix | transitive | 0.4.3 | 0.4.2, 0.4.3 | 0.4.3 | 0.4.3 | 0.4.3 |
| method_source | transitive | 1.1.0 | 1.1.0 | 1.1.0 | 1.1.0 | 1.1.0 |
| mini_magick | transitive | 5.3.1 | 5.3.1 | 5.4.0 | 5.4.0 | removed |
| mini_mime | transitive | 1.1.5 | 1.1.5 | 1.1.5 | 1.1.5 | 1.1.5 |
| minitest | transitive | 6.0.1 | 5.20.0, 6.0.1 | 6.1.0 | 6.1.0 | 6.1.0 |
| msgpack | transitive | 1.8.0 | 1.8.0 | 1.8.7 | 1.8.7 | 1.8.7 |
| net-imap | transitive | 0.6.2 | 0.4.9.1, 0.6.2 | 0.6.8 | 0.6.8 | 0.6.8 |
| net-pop | transitive | 0.1.2 | 0.1.2 | 0.1.2 | 0.1.2 | 0.1.2 |
| net-protocol | transitive | 0.2.2 | 0.2.2 | 0.4.0 | 0.4.0 | 0.4.0 |
| net-scp | transitive | 4.1.0 | 4.1.0 | 4.2.2 | 4.2.2 | 4.2.2 |
| net-sftp | transitive | 4.0.0 | 4.0.0 | 4.1.1 | 4.1.1 | 4.1.1 |
| net-smtp | transitive | 0.5.1 | 0.4.0.1, 0.5.1 | 0.5.2 | 0.5.2 | 0.5.2 |
| net-ssh | transitive | 7.3.0 | 7.3.0 | 7.3.10 | 8.1.2 | 8.1.2 |
| nio4r | transitive | 2.7.5 | 2.7.5 | 2.7.5 | 2.7.5 | 2.7.5 |
| nokogiri | transitive | 1.19.0 | 1.19.0 | 1.19.7 | 1.19.7 | 1.19.7 |
| openssl | new | — | — | — | 4.0.2 | 4.0.2 |
| ostruct | transitive | 0.6.3 | 0.6.0, 0.6.3 | 0.6.3 | 0.6.3 | 0.6.3 |
| parallel | transitive | 1.27.0 | 1.27.0 | 2.3.0 | 2.3.0 | 2.3.0 |
| parser | transitive | 3.3.10.0 | 3.3.10.0 | 3.3.13.0 | 3.3.13.0 | 3.3.13.0 |
| pg | direct: `~> 1.1` | 1.6.3 | 1.6.3 | 1.7.0 | 1.7.0 | 1.7.0 |
| pp | transitive | 0.6.3 | 0.5.0, 0.6.3 | 0.6.4 | 0.6.4 | 0.6.4 |
| prettyprint | transitive | 0.2.0 | 0.2.0 | 0.2.1 | 0.2.1 | 0.2.1 |
| prism | transitive | 1.8.0 | 0.19.0, 1.8.0 | 1.8.0 | 1.8.0 | 2.1.0 |
| propshaft | direct: `>= 0` | 1.3.1 | 1.3.1 | 1.3.2 | 1.3.2 | 1.3.2 |
| pry | direct: `>= 0` | 0.16.0 | 0.16.0 | 0.16.1 | 0.16.1 | 0.16.1 |
| psych | transitive | 5.3.1 | 5.1.2, 5.3.1 | 5.3.1 | 5.3.1 | removed |
| public_suffix | transitive | 7.0.2 | 7.0.2 | 7.0.5 | 7.0.5 | 7.0.5 |
| puma | direct: `>= 5.0` | 7.2.0 | 7.2.0 | 8.1.1 | 8.1.1 | 8.1.1 |
| raabro | transitive | 1.4.0 | 1.4.0 | 1.5.0 | 1.5.0 | 1.5.0 |
| racc | transitive | 1.8.1 | 1.7.3, 1.8.1 | 1.8.1 | 1.8.1 | 1.8.1 |
| rack | transitive | 3.2.4 | 3.2.4 | 3.2.8 | 3.2.8 | 3.2.8 |
| rack-session | transitive | 2.1.1 | 2.1.1 | 2.1.2 | 2.1.2 | 2.1.2 |
| rack-test | transitive | 2.2.0 | 2.2.0 | 2.3.0 | 2.3.0 | 2.3.0 |
| rackup | transitive | 2.3.1 | 2.3.1 | 2.3.1 | 2.3.1 | 2.3.1 |
| rails | direct: `~> 8.1.2` | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| rails-dom-testing | transitive | 2.3.0 | 2.3.0 | 2.3.0 | 2.3.0 | 2.3.0 |
| rails-html-sanitizer | transitive | 1.6.2 | 1.6.2 | 1.7.2 | 1.7.2 | 1.7.2 |
| railties | transitive | 8.1.2 | 8.1.2 | 8.1.4.1 | 8.1.4.1 | 8.1.4.1 |
| rainbow | transitive | 3.1.1 | 3.1.1 | 3.1.1 | 3.1.1 | 3.1.1 |
| rake | transitive | 13.3.1 | 13.1.0, 13.3.1 | 13.4.2 | 13.4.2 | 13.4.2 |
| rbs | new | — | — | — | 4.2.0 | 4.2.0 |
| rdoc | transitive | 7.1.0 | 6.6.3.1, 7.1.0 | 8.1.0 | 8.1.0 | 8.1.0 |
| regexp_parser | transitive | 2.11.3 | 2.11.3 | 2.13.1 | 2.13.1 | 2.13.1 |
| reline | transitive | 0.6.3 | 0.5.7, 0.6.3 | 0.7.0 | 0.7.0 | 0.7.0 |
| rexml | transitive | 3.4.4 | 3.3.6, 3.4.4 | 3.4.4 | 3.4.4 | 3.4.4 |
| rspec-core | transitive | 3.13.6 | 3.13.6 | 3.13.7 | 3.13.7 | 3.13.7 |
| rspec-expectations | transitive | 3.13.5 | 3.13.5 | 3.13.6 | 3.13.6 | 3.13.6 |
| rspec-mocks | transitive | 3.13.7 | 3.13.7 | 3.13.9 | 3.13.9 | 3.13.9 |
| rspec-rails | direct: `>= 0` | 8.0.2 | 8.0.2 | 8.1.0 | 8.1.0 | 8.1.0 |
| rspec-support | transitive | 3.13.6 | 3.13.6 | 3.13.8 | 3.13.8 | 3.13.8 |
| rubocop | transitive | 1.82.1 | 1.82.1 | 1.92.2 | 1.92.2 | 1.92.2 |
| rubocop-ast | transitive | 1.49.0 | 1.49.0 | 1.51.0 | 1.51.0 | 1.51.0 |
| rubocop-performance | transitive | 1.26.1 | 1.26.1 | 1.27.0 | 1.27.0 | 1.27.0 |
| rubocop-rails | transitive | 2.34.3 | 2.34.3 | 2.38.0 | 2.38.0 | 2.38.0 |
| rubocop-rails-omakase | direct: `>= 0` | 1.1.0 | 1.1.0 | 1.1.0 | 1.1.0 | 1.1.0 |
| ruby-progressbar | transitive | 1.13.0 | 1.13.0 | 1.13.0 | 1.13.0 | 1.13.0 |
| ruby-vips | transitive | 2.3.0 | 2.3.0 | 2.3.0 | 2.3.0 | 2.3.0 |
| rubyzip | transitive | 3.7.0 | 3.7.0 | 3.7.0 | 3.7.0 | 3.7.0 |
| securerandom | transitive | 0.4.1 | 0.3.1, 0.4.1 | 0.4.1 | 0.4.1 | 0.4.1 |
| selenium-webdriver | direct: `>= 0` | 4.52.0 | 4.52.0 | 4.52.0 | 4.52.0 | 4.52.0 |
| solid_cable | direct: `>= 0` | 3.0.12 | 3.0.12 | 4.1.0 | 4.1.0 | 4.1.0 |
| solid_cache | direct: `>= 0` | 1.0.10 | 1.0.10 | 1.0.10 | 1.0.10 | 1.0.10 |
| solid_queue | direct: `>= 0` | 1.3.1 | 1.3.1 | 1.7.2 | 1.7.2 | 1.7.2 |
| sshkit | transitive | 1.25.0 | 1.25.0 | 1.25.1 | 1.25.1 | 1.25.1 |
| stimulus-rails | direct: `>= 0` | 1.3.4 | 1.3.4 | 1.3.4 | 1.3.4 | 1.3.4 |
| stringio | transitive | 3.2.0 | 3.1.1, 3.2.0 | 3.2.0 | 3.2.0 | removed |
| thor | transitive | 1.5.0 | 1.5.0 | 1.5.0 | 1.5.0 | 1.5.0 |
| thruster | direct: `>= 0` | 0.1.17 | 0.1.17 | 0.1.27 | 0.1.27 | removed |
| timeout | transitive | 0.6.0 | 0.4.1, 0.6.0 | 0.6.1 | 0.6.1 | 0.6.1 |
| tsort | transitive | 0.2.0 | 0.2.0 | 0.2.0 | 0.2.0 | 0.2.0 |
| turbo-rails | direct: `>= 0` | 2.0.23 | 2.0.23 | 2.0.23 | 2.0.23 | 2.0.23 |
| tzinfo | transitive | 2.0.6 | 2.0.6 | 2.0.6 | 2.0.6 | 2.0.6 |
| unicode-display_width | transitive | 3.2.0 | 3.2.0 | 3.3.0 | 3.3.0 | 3.3.0 |
| unicode-emoji | transitive | 4.2.0 | 4.2.0 | 4.3.0 | 4.3.0 | 4.3.0 |
| uri | transitive | 1.1.1 | 0.13.1, 1.1.1 | 1.1.2 | 1.1.2 | 1.1.2 |
| useragent | transitive | 0.16.11 | 0.16.11 | 0.16.11 | 0.16.11 | 0.16.11 |
| web-console | direct: `>= 0` | 4.2.1 | 4.2.1 | 4.3.0 | 4.3.0 | 4.3.0 |
| webmock | direct: `>= 0` | 3.26.1 | 3.26.1 | 3.34.0 | 3.34.0 | 3.34.0 |
| websocket | transitive | 1.2.11 | 1.2.11 | 1.2.11 | 1.2.11 | 1.2.11 |
| websocket-driver | transitive | 0.8.0 | 0.8.0 | 0.8.2 | 0.8.2 | 0.8.2 |
| websocket-extensions | transitive | 0.1.5 | 0.1.5 | 0.1.5 | 0.1.5 | 0.1.5 |
| xpath | transitive | 3.2.0 | 3.2.0 | 3.2.0 | 3.2.0 | 3.2.0 |
| zeitwerk | transitive | 2.7.4 | 2.7.4 | 2.8.3 | 2.8.3 | 2.8.3 |

Updated **88** existing gem/toolchain names; removed 9; added 3. Before 148 distinct names including Bundler, after 142 locally selected names including Bundler. Extra native-platform lock records are not separate package upgrades.

Removed: ed25519, ffi-compiler, http-form_data, kamal, llhttp-ffi, mini_magick, psych, stringio, thruster.

Added: llhttp, openssl, rbs.

ruby-vips and bcrypt_pbkdf become explicit dependencies (previously transitive): retain the Rails vips backend lazily, and encrypted SSH private-key support after removing Kamal. The separate ed25519 gem is no longer needed because Net::SSH 8 uses OpenSSL Ed25519 support. psych/stringio may remain Ruby default libraries; removal from the bundle does not remove them from the interpreter.
