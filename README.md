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
- `spp/` subtrees are fenced out of the base sweep. With `--spp NAME`, reconcile narrows the SPP sweep to the requested per-SPP subtree(s), leaving `SPP-PLACEHOLDER` and unrequested SPP siblings intact; without `--spp`, only the `SPP-PLACEHOLDER` subtree is swept. Deleted-SPP cleanup remains a manual `git rm` in the teardown runbook. See ADR-0002.
- If any rendered entry resolves to a path outside its scope prefix (a full-path or relative `..` escape), reconcile hard-errors before deleting anything.

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
