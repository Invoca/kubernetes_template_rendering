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
    --rendered_directory path/to/resources \
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

- `--reconcile` and `--prune` are mutually exclusive (passing both exits with an error).
- `spp/` subtrees are fenced out of the sweep; deleted-SPP cleanup remains a manual `git rm` in the teardown runbook.
- If any rendered entry resolves to a path outside its scope prefix (a full-path or relative `..` escape), reconcile hard-errors before deleting anything.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/invoca/kubernetes_template_rendering>.
