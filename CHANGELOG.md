# CHANGELOG for `kubernetes_template_rendering`

Inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Note: this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
