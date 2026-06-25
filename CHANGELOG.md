# CHANGELOG for `kubernetes_template_rendering`

Inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Note: this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-06-25
### Added
- Added a `subdirectory:` option to `definitions.yaml`. It is mutually exclusive with `directory:` and sets the output path to the base path `%{plain_region}/%{type}/%{color}/<subdirectory>`. When neither `directory:` nor `subdirectory:` is given, output is rendered to the base path `%{plain_region}/%{type}/%{color}` (previously a missing `directory:` raised an error).

## [0.3.0] - 2026-06-24
### Fixed
- Ruby 4.0 compatibility: declare `ostruct` as a dependency (it is `require`d directly but was removed from Ruby's default gems in 4.0.0) and bump `activesupport` to `7.2.3.1` so its `logger` dependency is resolved (`logger` was likewise dropped from default gems).

### Removed
- No longer emit the `# Variable overrides used:` comment in rendered files. Because overrides such as `deploySha` change on every build, this comment caused large, content-free diffs across every rendered file. `--variable-override` still applies the overrides to the rendered output; only the comment is removed.

## [0.2.5] - 2025-05-08
### Fixed
- Updated `rexml` dependency to avoid security issues

## [0.2.4] - 2025-05-08
### Fixed
- Fixed `--prune` to properly remove files in the rendered directory

## [0.2.3] - 2025-03-25
### Fixed
- Fixed `--variable-override` to accept multiple arguments to override multiple variables

## [0.2.2] - 2024-06-17
### Fixed
- Fixed a bug allowing child process errors to be ignored while rendering.

## [0.2.1] - 2024-11-22
### Fixed
- Fixed a bug where attempting to use `activesupport` 8 was causing installation issues

## [0.2.0] - 2024-05-06
### Added
- Added support for passing `--source-repo` flag into command line so that the rendered manifest comments can include a link to the source repository.

### Changed
- Updated the code comment to include the variable overrides used when rendering the current version of the templates

## [0.1.0] - 2024-04-22

- Initial release
