# `subdirectory` option for definitions.yaml — Design

## Summary

Add a new optional `subdirectory` field to `definitions.yaml` and introduce a
base-path default for the output directory. `subdirectory` is mutually exclusive
with the existing `directory` field. When `subdirectory` is set (or when neither
field is set), the output directory is derived from `plain_region`,
`kubernetes_cluster_type`, and `color` instead of from a hand-written `directory`
pattern.

## Motivation

Today every `definitions.yaml` entry must declare a full `directory:` pattern such
as `%{plain_region}/%{type}/%{color}/staging-ops`. The `%{plain_region}/%{type}/%{color}`
prefix is boilerplate repeated across nearly every entry. `subdirectory` lets an
author specify only the final path segment and have the common prefix supplied
automatically; omitting both fields renders straight to that common base path.

## Resolution rules

Resolved in `ResourceSet#initialize` when computing `@target_output_directory`:

| Config present | Resulting output-directory pattern |
|---|---|
| `directory` only | the `directory` value, verbatim (unchanged from today) |
| `subdirectory` only | `%{plain_region}/%{type}/%{color}/<subdirectory>` |
| neither | `%{plain_region}/%{type}/%{color}` (base path) |
| both | `ArgumentError` (mutually exclusive) |

Conceptually:

```ruby
base = File.join("%{plain_region}", "%{type}", "%{color}")
@target_output_directory =
  if directory && subdirectory
    raise ArgumentError, "...only one of 'directory:' or 'subdirectory:'..."
  elsif directory
    directory
  elsif subdirectory
    File.join(base, subdirectory)
  else
    base
  end
```

- `<subdirectory>` is treated as a **plain literal** final segment — no `%{...}`
  interpolation is performed on the value itself. It may contain slashes if the
  author wants additional nesting, but that is incidental, not a feature.
- The resulting pattern still flows through the **existing** `format(...)` call in
  `ResourceSet#render`, so per region/color it expands exactly like a `directory`
  pattern does. Example: `subdirectory: my-app` with region `us-east-1`,
  cluster_type `prod`, color `orange` → `us-east-1/prod/orange/my-app`.

## Behavior change

This **removes** the current "missing `directory:` → raise `ArgumentError`"
behavior (`resource_set.rb:23`). A definitions entry with neither field now
renders to the base path rather than erroring. The only remaining error case is
specifying **both** `directory` and `subdirectory`.

## Scope

**In scope**
- `ResourceSet#initialize` directory-resolution logic.
- Class docstring atop `resource_set.rb` documenting the three modes.
- `resource_set_spec.rb` test coverage.
- CHANGELOG entry.

**Out of scope**
- `normal_render` — currently dead code (never called); not modified.
- CLI flags — `subdirectory` is a `definitions.yaml` field, not a command-line option.

## Unchanged behavior

- The `format(...)` interpolation in `render` (keys: `plain_region`, `type`, `color`).
- The kube-platform `%{plain_region}` validation (`resource_set.rb:33-34`): the
  base path always contains `%{plain_region}`, so subdirectory/default modes pass it.
- Directory creation and `--prune` handling.

## Testing (TDD)

Add contexts to `spec/kubernetes_template_rendering/resource_set_spec.rb`:

1. `directory` only → expands to the `directory` pattern (existing behavior preserved).
2. `subdirectory` only → expands to `<plain_region>/<type>/<color>/<subdirectory>`.
3. neither field → expands to `<plain_region>/<type>/<color>` (base path).
4. both fields → raises `ArgumentError`.
