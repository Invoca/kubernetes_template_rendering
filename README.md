# KubernetesTemplateRendering

The `invoca-kubernetes_template` gem is a thin wrapper around `jsonnet` and `erb` to allow for the generation of
Kubernetes manifests from a set of templates combined with a `definitions.yaml` file which stores environmental
configuration for various deployment environments.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add kubernetes_template_rendering
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install kubernetes_template_rendering
```

## Usage

This gem is meant to be used as a command line tool for rendering templates that are either written in `jsonnet` or `erb`.
To use this gem you can either install it, and use the `render_kubernetes_template` executable directly, or you can use
`gem exec` to execute the command without first installing the gem.

### Example Usage

```bash
gem exec -g kubernetes_template_rendering render_templates \
    --jsonnet-library-path deployment/vendor \
    --rendered-directory path/to/resources \
    deployment/templates
```

### Options

To see a full list of options and how to use them, run the following command:

```bash
gem exec -g kubernetes_template_rendering render_templates --help
```

### Cleaning up stale output: `--prune` vs `--reconcile`

Both flags remove output left over from templates/entries that no longer render, but they differ in how:

- `--prune` deletes each entry's output directory with `rm -rf` **before** rendering. It never removes the directories of fully deleted/renamed entries and can clobber sibling directories when one entry renders at a prefix root above another.
- `--reconcile` performs a safer, bounded sweep: it touches a marker, renders, then deletes only files older than the marker under each scope root `<region>/<cluster_type>/<color>/` (honoring `--cluster_type` / `--region` / `--color`), and finally removes any now-empty directories. This cleans up directories of deleted/renamed entries without clobbering freshly-rendered siblings, and two identical reconcile runs produce the same result.

Notes:

- `--reconcile` and `--prune` are mutually exclusive (passing both exits with an error). `--reconcile` and `--only` are likewise mutually exclusive, since a filtered render would leave un-rendered siblings looking stale under the shared base root.
- `spp/` subtrees are fenced out of the base sweep. Without `--spp`, only the `SPP-PLACEHOLDER` subtree is swept. With `--spp NAME`, reconcile sweeps `SPP-PLACEHOLDER` (always re-rendered, as the expansion source) plus each requested per-SPP subtree, leaving unrequested SPP siblings intact. Deleted-SPP cleanup for unrequested siblings remains a manual `git rm` in the teardown runbook. See ADR-0002.
- If any rendered entry resolves to a path outside its scope prefix (a full-path or relative `..` escape), reconcile hard-errors before deleting anything.
- Reconcile enforces the SPP layout: every SPP entry (name contains `SPP-PLACEHOLDER`) must render under `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/`, and no non-SPP entry may render under an `spp/` segment. A `directory:` override that still resolves to that prefix is allowed; anything else hard-errors before rendering. (This guard runs only under `--reconcile`.) See ADR-0002.

### Filtering to specific entries

Pass `--only NAME` (repeatable) to render only the `definitions.yaml` entries whose top-level key exactly matches `NAME`. Composes with `--cluster_type`/`--region`/`--color`/`--spp` — all filters are AND'd.

```bash
gem exec -g kubernetes_template_rendering render_templates \
    --rendered-directory path/to/resources \
    --cluster_type staging \
    --only staging.test \
    deployment/templates
```

Useful when one `--cluster_type` matches multiple sibling entries (e.g. `staging` and `staging.test` both match `--cluster_type staging` after the suffix-strip rule) and you want to render only one of them. Repeated `--only` values are deduped.

If an `--only` value matches no entry across any template directory, the gem raises with the list of valid keys so the caller can self-correct.

### Variable overrides

Pass `--variable-override KEY:VALUE` (repeatable) to override values from `definitions.yaml` after all per-section variables and auto-injected region/cluster vars are resolved. Overrides always win.

**Legacy form (no dot in KEY):** sets a top-level key to the raw string value — exactly the pre-0.7.0 behavior. Values are never type-coerced (`deploySha:12345` stays the string `"12345"`; `enabled:true` stays `"true"`). The value is everything after the first colon (`image:registry:5000/app` → `"registry:5000/app"`). Arguments with no colon are silently ignored.

```bash
gem exec -g kubernetes_template_rendering render_templates \
    --rendered-directory path/to/resources \
    --variable-override deploySha:abc123 \
    deployment/templates
```

**Dotted-path form (KEY contains `.`):** the key is split on unescaped dots into a nested path and deep-merged into variables. The value is JSON-coerced when it parses as JSON (`2` → integer, `true`/`false` → booleans, `null` → nil, `"2"` → string); otherwise the raw string is kept (`hello` → `"hello"`, `02` → `"02"`).

```bash
gem exec -g kubernetes_template_rendering render_templates \
    --rendered-directory path/to/resources \
    --variable-override components.webServer.hpa.minReplicas:2 \
    deployment/templates
```

Escape literal dots in a segment with `\.` (e.g. `metadata.labels.app\.kubernetes\.io/name:foo`). Only `\.` is an escape sequence; all other backslashes — including trailing ones — are kept literally. Keys that would need a literal backslash immediately before a path-splitting dot must use `--variable-override-json` instead.

**`--variable-override-json` (repeatable):** deep-merges a JSON object. Use this for values containing commas or whole arrays/objects (the legacy Array acceptor comma-splits `KEY:VALUE` arguments).

```bash
gem exec -g kubernetes_template_rendering render_templates \
    --rendered-directory path/to/resources \
    --variable-override-json '{"ephemeral":{"mysql":{"enabled":true}}}' \
    deployment/templates
```

**Precedence:** all override flags are folded into one hash in command-line order via deep merge (later flags win on conflict), then deep-merged last over the fully-resolved variables.

Overrides are echoed once to stdout at render start (`Variable overrides (deep-merged after definitions.yaml): {...}`). Rendered files carry no override comment (removed in [0.3.0](CHANGELOG.md#030---2026-06-24) to avoid content-free diffs on every deploy).

### Staging Partial Platforms

Pass `--spp NAME` (repeatable) to expand any entry whose `definitions.yaml` name contains `SPP-PLACEHOLDER` into a per-SPP sibling output. Substitutes `SPP-PLACEHOLDER` with `NAME` and the `PLACEHOLDER` suffix with the suffix of `NAME` (everything after the last `-`), in both file paths and contents. Source mtimes are preserved.

```bash
gem exec -g kubernetes_template_rendering render_templates \
    --rendered-directory path/to/resources \
    --spp staging-qa02a \
    --spp staging-qa08a \
    deployment/templates
```

This is purely additive — the placeholder-bearing output tree is still produced, and per-SPP trees are written alongside it. Repeated `--spp` values are deduped.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/invoca/kubernetes_template_rendering>.
