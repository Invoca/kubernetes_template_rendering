# CHANGELOG for `kubernetes_template_rendering`

Inspired by [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

Note: this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.0] - 2026-07-23
### Added
- `--variable-override` now supports dotted-path keys (`components.webServer.hpa.minReplicas:2`) that deep-merge into nested variables, with JSON value coercion (integers, floats, booleans, `null`, quoted strings; non-JSON values stay raw strings) and `\.` escaping for literal dots. Plain `KEY:VALUE` (no dot) behaves exactly as before: top-level key, raw string value.
- Added `--variable-override-json '<json object>'` (repeatable), deep-merged with all other override flags in command-line order (later flags win). Use it for values containing commas or whole structures.
- Overrides are echoed once to stdout at render start (`Variable overrides (deep-merged after definitions.yaml): {...}`). Rendered files still carry no override comment (see 0.3.0).

### Changed
- `Template#initialize` merges `variable_overrides` with `deep_merge` instead of `merge`. Behavior-identical for all previously-valid inputs (legacy override values are always strings, so no hash-vs-hash merge could occur).

## [0.6.2] - 2026-07-15
### Fixed
- Fixed the `--reconcile` sweep root for entries whose `subdirectory:` nests more than one level deep (e.g. `subdirectory: exclude-argocd/auth`). The sweep root is now the entry's canonical base — `<region>/<cluster_type>/<color>` for non-SPP entries and `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER` for SPP entries — regardless of `subdirectory:` depth, rather than the immediate parent of the rendered output directory. Previously a nested `subdirectory:` pushed the sweep root one level too deep, so when a `subdirectory:` was renamed or nested deeper the files left at the old shallower path were siblings of the sweep root and were never swept.

### Changed
- Under `--reconcile`, non-SPP entries must now render within their canonical `<region>/<cluster_type>/<color>` base; an entry that renders outside it (only reachable via the deprecated `directory:` field) hard-errors before any writes. This completes the reconcile layout hard-validation deferred in ADR-0001 — SPP entries were already constrained to the `spp/SPP-PLACEHOLDER` prefix. See ADR-0001.

## [0.6.1] - 2026-07-08
### Fixed
- Fixed `variable_overrides` and `source_repo` not being forwarded to child `Resource` instances created by `DeployGroupedResource`. Previously, `--variable-override` values (e.g. `deploySha`) were silently unavailable inside all `*-deploy.jsonnet` and `*-deploy.yaml.erb` templates, causing a `KeyError` at render time. `DeployGroupedResource#initialize` now accepts both as optional keyword arguments and passes them through to each `Resource.new` call in `#render`. `ResourceSet#grouped_resources` is updated to supply both values.

## [0.6.0] - 2026-07-06
### Added
- Added `--reconcile` flag: a bounded, marker-based sweep that replaces the destructive per-entry `rm -rf` of `--prune`. It touches a marker before rendering, then after rendering deletes only files older than the marker under each scope root (`<region>/<cluster_type>/<color>/`) and removes empty directories, correctly cleaning up directories of deleted/renamed entries. `spp/` subtrees are fenced out of the base sweep, paths resolving outside their scope prefix raise a hard error, and `--reconcile` combined with `--prune` is rejected.
- Made `--reconcile` `--spp`-aware: without `--spp` only the `SPP-PLACEHOLDER` subtree is swept; with `--spp NAME` the sweep covers `SPP-PLACEHOLDER` (always re-rendered, as the expansion source) plus each requested per-SPP subtree (substituting `SPP-PLACEHOLDER` into the sweep root), leaving unrequested SPP siblings intact. Rejected `--reconcile` combined with `--only`, which would delete un-rendered siblings under the shared base root. See ADR-0002.
- Added a `--reconcile` SPP layout guard: SPP entries (name contains `SPP-PLACEHOLDER`) must render under `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/`, and non-SPP entries must not render under any `spp/` segment. A `directory:` override that still resolves to the canonical SPP prefix is allowed; anything else hard-errors before rendering. The guard runs only under `--reconcile`. See ADR-0002.

## [0.5.0] - 2026-06-26
### Added
- Added `--spp NAME` (repeatable) flag that expands rendered output of `SPP-PLACEHOLDER` entries into per-Staging-Partial-Platform sibling directories, substituting `SPP-PLACEHOLDER` and its `PLACEHOLDER` suffix in both paths and contents. Composes with the SPP-derived base path introduced in 0.4.0 (sibling per-SPP trees are created next to the literal `SPP-PLACEHOLDER` segment). Replaces the post-render `invocaops_docker/tools/spp-transform/spp-transform.rb` step inside the gem.
- Added `--only NAME` (repeatable) flag that filters rendering to specific top-level `definitions.yaml` entries by exact key match. Composes with `--cluster_type`/`--region`/`--color`/`--spp` (all filters are AND'd). Raises with a list of valid keys if any `--only` value matches no entry across the rendered template directories.

## [0.4.0] - 2026-06-25
### Added
- Added a `subdirectory:` option to `definitions.yaml`. It is mutually exclusive with `directory:` and sets the output path to the base path `%{plain_region}/%{type}/%{color}/<subdirectory>`. When neither `directory:` nor `subdirectory:` is given, output is rendered to the base path `%{plain_region}/%{type}/%{color}` (previously a missing `directory:` raised an error).
- Emit a deprecation warning on any use of `directory:` in `definitions.yaml`, suggesting to remove it (to render into the standard `%{plain_region}/%{type}/%{color}` layout) or switch to `subdirectory:`. `directory:` is the only way to produce a non-standard path, which is unsafe for the planned `--reconcile` stale-resource deletion. See ADR-0001.
- SPP definitions (those whose name contains the `SPP-PLACEHOLDER` token) now render under a derived base path `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`, with `subdirectory:` composing on top. This keeps each SPP instance's output distinct and bounded under the `region/type/color` tree for `--reconcile`, and preserves the literal `SPP-PLACEHOLDER` token for downstream per-instance substitution. The `directory:` deprecation warning now points SPP definitions at the SPP base layout. See ADR-0001.

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
