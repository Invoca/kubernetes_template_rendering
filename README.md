# Invoca::KubernetesTemplates

The `invoca-kubernetes_template` gem is a thin wrapper around `jsonnet` and `erb` to allow for the generation of
Kubernetes manifests from a set of templates combined with a `definitions.yaml` file which stores environmental
configuration for various deployment environments.

## Installation

Install the gem and add to the application's Gemfile by executing:
```
bundle add invoca-kubernetes_templates
```

If bundler is not being used to manage dependencies, install the gem by executing:
```
gem install invoca-kubernetes_templates
```

## Usage

This gem is meant to be used as a command line tool for rendering templates that are either written in `jsonnet` or `erb`.
To use this gem you can either install it, and use the `render_kubernetes_template` executable directly, or you can use
`gem exec` to execute the command without first installing the gem.

### Example Usage
```bash
gem exec -g invoca-kubernetes_templates render_kubernetes_templates -- \
    --jsonnet-library-path deployment/vendor \
    --rendered_directory path/to/resources \
    deployment/templates
```

### Options

To see a full list of options and how to use them, run the following command:
```bash
gem exec -g invoca-kubernetes_templates render_kubernetes_templates -- --help
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/invoca/invoca-kubernetes_templates.
