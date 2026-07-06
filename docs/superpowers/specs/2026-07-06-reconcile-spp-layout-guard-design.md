# Reconcile SPP layout guard

* Status: approved
* Date: 2026-07-06
* Related: OCTO-842, [ADR-0001](../../adrs/0001-strict-rendering-paths-for-stale-resource-deletion.md), [ADR-0002](../../adrs/0002-spp-aware-reconcile-scopes-and-only-guard.md)

## Problem

Nothing currently enforces that Staging Partial Platform (SPP) resources render under the
canonical `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/…` layout.

- An entry is classified as SPP purely by its `definitions.yaml` key name containing the literal
  `SPP-PLACEHOLDER` token (`template_directory_renderer.rb`, `spp = name.include?(ResourceSet::SPP_PLACEHOLDER)`).
- The output path is resolved by `ResourceSet#resolve_target_output_directory`. For entries using
  `subdirectory:` or no directory config, the `spp/SPP-PLACEHOLDER` segment is guaranteed by
  construction via `SPP_BASE_OUTPUT_DIRECTORY`. But the deprecated `directory:` escape hatch returns
  its pattern verbatim, ignores the `@spp` flag, and only prints a warning — so an SPP entry can
  render anywhere, and a non-SPP entry can be smuggled under `spp/`.

For `--reconcile` this is a correctness/safety concern: the bounded sweep reasons about SPP subtrees
by path, so an off-layout SPP entry (or a non-SPP entry under `spp/`) breaks the sweep's assumptions.

## Decisions

1. **Gate on `--reconcile` only.** Plain renders are unaffected; the guard runs solely on the
   reconcile code path, before the marker is captured and before any files are written.
2. **Enforce both directions.**
   - Forward: every SPP entry (name contains `SPP-PLACEHOLDER`) must resolve to
     `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/…`.
   - Converse: a non-SPP entry must not resolve beneath any `spp/` segment.
3. **Validate shape, don't ban `directory:`.** A `directory:`-overridden path is allowed as long as
   it still resolves to the canonical SPP prefix. Only non-conforming shapes are a hard error.
4. **Implementation locus:** the renderer's existing reconcile validation pass
   (`collect_reconcile_scopes`), using an `spp:` flag and a canonical `spp_base_root:` carried on
   each scope hash. Chosen over enforcing inside `ResourceSet` (which lacks `--reconcile` state) and
   over segment-index checks (fragile if a region value ever contains a slash).

## Design

### 1. Extend the reconcile scope hash — `lib/kubernetes_template_rendering/resource_set.rb`

`reconcile_scopes` gains two fields per scope so the renderer needs no re-derivation of
region/type/color:

```ruby
def reconcile_scopes
  @regions.flat_map do |plain_region|
    @colors.map do |c|
      output_directory = File.join(@rendered_directory, format(@target_output_directory, plain_region: plain_region, color: c, type: @kubernetes_cluster_type))
      spp_base_root    = File.join(@rendered_directory, format(SPP_BASE_OUTPUT_DIRECTORY, plain_region: plain_region, color: c, type: @kubernetes_cluster_type))
      { base_root: File.dirname(output_directory), output_directory: output_directory, spp: @spp, spp_base_root: spp_base_root }
    end
  end
end
```

`spp_base_root` is the canonical `<rendered>/<region>/<type>/<color>/spp/SPP-PLACEHOLDER` for that
region/color, computed identically regardless of how the entry configured its output path.
`SPP_BASE_OUTPUT_DIRECTORY` contains only `%{plain_region}`/`%{type}`/`%{color}` placeholders plus
the literal `SPP-PLACEHOLDER` token (no `%`), so `format` substitutes cleanly.

### 2. Enforcement — `lib/kubernetes_template_rendering/template_directory_renderer.rb`

`collect_reconcile_scopes` adds a second validation pass after the existing path-escape pass (so an
escape still errors first):

```ruby
scopes.each { |scope| validate_within_scope!(scope[:base_root], @rendered_directory) }
scopes.each { |scope| validate_spp_layout!(scope) }
```

```ruby
# Under --reconcile, SPP entries must render beneath the canonical
# <region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/ prefix, and non-SPP entries must never
# render beneath any spp/ segment. A directory:-overridden path that still resolves to the
# canonical SPP prefix is allowed; anything else is a hard error before any writes.
def validate_spp_layout!(scope)
  output = File.expand_path(scope[:output_directory])
  if scope[:spp]
    base = File.expand_path(scope[:spp_base_root])
    unless output == base || output.start_with?(base + File::SEPARATOR)
      raise Reconciler::SppLayoutError,
            "reconcile: SPP entry renders to #{output}, outside the required SPP prefix #{base}"
    end
  elsif within_spp_subtree?(scope[:output_directory])
    raise Reconciler::SppLayoutError,
          "reconcile: non-SPP entry renders under an spp/ segment (#{output}); only SPP entries may render beneath spp/"
  end
end
```

The forward check reuses the canonical prefix; the converse reuses the existing
`within_spp_subtree?` (true when any relative path segment equals `"spp"`).

### 3. Error type — `lib/kubernetes_template_rendering/reconciler.rb`

Add alongside `OutOfScopeError`:

```ruby
class SppLayoutError < StandardError; end
```

Semantically distinct from a path escape, but same namespace and same abort-before-writing behavior.

## Tests (TDD — write before implementation)

**`spec/kubernetes_template_rendering/resource_set_spec.rb`**
- `reconcile_scopes` includes `spp: true` and the correct `spp_base_root:` for an SPP resource set.
- `reconcile_scopes` includes `spp: false` for a non-SPP resource set.

**`spec/kubernetes_template_rendering/template_directory_renderer_spec.rb`** (all under `--reconcile`)
- SPP entry resolving to `.../spp/SPP-PLACEHOLDER/…` → no error.
- SPP entry via `directory:` that still conforms to the SPP prefix → allowed.
- SPP entry via `directory:` pointing outside the prefix → raises `SppLayoutError`; nothing written or deleted.
- Non-SPP entry via `directory:` landing under `spp/` → raises `SppLayoutError`.
- Plain non-SPP entry → no error.
- Without `--reconcile`: a non-conforming SPP entry still renders (guard does not run).

## Docs

- README: add a bullet to the `--prune` vs `--reconcile` section noting the layout guard.
- CHANGELOG: line under `[0.6.0] - Unreleased`.

## Out of scope

- Enforcing the layout on non-reconcile renders.
- Removing or further restricting the deprecated `directory:` escape hatch beyond shape validation.
- Any change to SPP classification (still by `SPP-PLACEHOLDER` in the entry name).
