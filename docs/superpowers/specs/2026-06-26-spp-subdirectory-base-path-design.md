# SPP definitions get a derived `spp/SPP-PLACEHOLDER` base output path

* Status: approved
* Date: 2026-06-26
* Related: OCTO-849, [ADR-0001](../../adrs/0001-strict-rendering-paths-for-stale-resource-deletion.md), the `subdirectory:` option

## Problem

`TemplateDirectoryRenderer` derives a definition's `kubernetes_cluster_type` from its
name: a definition named `SPP-PLACEHOLDER` (or `SPP-PLACEHOLDER.eu`) maps to cluster
type `staging` via `name.sub('SPP-PLACEHOLDER', 'staging').sub(/\..*/, '')`.

With the strict/derived output paths from ADR-0001, a definition's output directory is
resolved from the mutually-exclusive `directory:`/`subdirectory:` fields, defaulting to
the base path `%{plain_region}/%{type}/%{color}`. For an SPP definition that default is
**actively wrong**:

* `%{type}` resolves to `staging`, so an SPP definition with no `directory:`/`subdirectory:`
  renders to `%{plain_region}/staging/%{color}` — colliding with real `staging` resources.
* The `SPP-PLACEHOLDER` token, which downstream deploy tooling substitutes per SPP
  instance, never appears in the rendered path, so there is nothing to substitute.

The `SPP-PLACEHOLDER` token in the path is a literal: `format(...)` (resource_set.rb)
only substitutes `plain_region`/`type`/`color`, so `spp/SPP-PLACEHOLDER` survives into
the rendered tree verbatim — exactly what downstream substitution requires.

We want SPP definitions to always render under `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`,
keeping the output deterministic and bounded under the `region/type/color` tree so
`--reconcile` (ADR-0001) can still safely enumerate and delete only stale resources.

## Decision

For SPP definitions — identified by the definition name containing the `SPP-PLACEHOLDER`
token, the same signal already used to derive the `staging` cluster type — the base
output path becomes `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER` instead of the
plain `%{plain_region}/%{type}/%{color}`. The `directory:`/`subdirectory:` resolution is
otherwise unchanged; `subdirectory:` composes on top of the SPP base exactly as it does
on the standard base.

### Resolution contract

For non-SPP definitions, behavior is unchanged. For SPP definitions:

| Config present       | Non-SPP (unchanged)                | SPP definition (new)                                       |
|----------------------|------------------------------------|------------------------------------------------------------|
| neither              | `%{plain_region}/%{type}/%{color}` | `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`      |
| `subdirectory` only  | `…/%{color}/<sub>`                 | `…/spp/SPP-PLACEHOLDER/<sub>`                               |
| `directory` only     | the value verbatim + deprecation warning | the value verbatim + deprecation warning            |
| both                 | `ArgumentError`                    | `ArgumentError`                                            |

For SPP definitions, `%{type}` resolves to `staging`, so e.g. with region `us-east-1`,
color `orange`, and no `subdirectory:` the rendered path is
`us-east-1/staging/orange/spp/SPP-PLACEHOLDER`. With `subdirectory: my-app` it is
`us-east-1/staging/orange/spp/SPP-PLACEHOLDER/my-app`.

### `.eu` and other name suffixes

A name suffix after a `.` (e.g. `SPP-PLACEHOLDER.eu`) only distinguishes the definition
entry and its `regions:`/`colors:`; it is stripped when deriving the cluster type and
does **not** appear in the output path. The path segment stays the literal
`SPP-PLACEHOLDER`, and region differentiation in the path comes from `%{plain_region}`.
So `SPP-PLACEHOLDER` and `SPP-PLACEHOLDER.eu` both contribute the same
`spp/SPP-PLACEHOLDER` segment, differentiated on disk only by their (non-overlapping)
regions.

### Enforcement rollout (warn-only first)

The derived default and the `subdirectory:` composition are correct by construction, so
the only way to produce a non-conforming SPP path is the legacy `directory:` escape
hatch — which already emits a deprecation warning on *any* use. We extend that warning so
that for SPP definitions it points authors at the SPP base layout
(`%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`) rather than the plain
`%{plain_region}/%{type}/%{color}` layout, which would be wrong guidance for an SPP
author.

Hard rejection of a non-conforming `directory:` remains the documented follow-up
(consistent with ADR-0001's deferred hard-validation step); this change is warn-only.

## Implementation

* **Shared constant.** Promote the duplicated `'SPP-PLACEHOLDER'` literal (currently two
  occurrences in `template_directory_renderer.rb`) to a named constant so the renderer and
  the path builder reference the same token.
* **Thread the SPP signal into `ResourceSet`.** `TemplateDirectoryRenderer` already has the
  definition `name` where it derives `kubernetes_cluster_type`. It also derives
  `spp: name.include?(SPP_PLACEHOLDER)` and passes it to `ResourceSet.new`. Passing a
  boolean keeps `ResourceSet` from re-implementing the name-parsing rules.
* **`ResourceSet` selects the base.** In `resolve_target_output_directory`, when `spp?`,
  the base is `File.join(BASE_OUTPUT_DIRECTORY, "spp", SPP_PLACEHOLDER)`; otherwise the
  existing `BASE_OUTPUT_DIRECTORY`. The `directory`/`subdirectory`/`both`/`neither`
  branching is otherwise unchanged.
* **Refine the deprecation warning** (`warn_directory_deprecated`) so the suggested
  "remove it to render into …" layout reflects the SPP base when the definition is SPP.
* The existing `%{plain_region}` guard still holds: the SPP base contains `%{plain_region}`,
  and SPP cluster type `staging` is not `kube-platform`.

### Components touched

* `lib/kubernetes_template_rendering/template_directory_renderer.rb` — SPP constant, derive
  `spp:`, pass it to `ResourceSet.new`.
* `lib/kubernetes_template_rendering/resource_set.rb` — accept `spp:`, select SPP base in
  `resolve_target_output_directory`, SPP-aware deprecation warning.

## Testing

* `resource_set_spec.rb`:
  * SPP `spp: true` with neither field → base `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`.
  * SPP `spp: true` with `subdirectory: <sub>` → `…/spp/SPP-PLACEHOLDER/<sub>`.
  * SPP `spp: true` with `directory:` → verbatim + (SPP-flavored) deprecation warning.
  * Regression: non-SPP (`spp: false`) neither/subdirectory cases unchanged.
* `template_directory_renderer_spec.rb`: extend the existing name→cluster_type table so the
  `ResourceSet.new` expectation also asserts the correct `spp:` flag — `true` for
  `SPP-PLACEHOLDER` and `SPP-PLACEHOLDER.eu`, `false` for `test` and `prod.gcp`.

## Docs

* Update **ADR-0001** with the SPP base-path row and note that the warn-only-then-reject
  rollout extends to SPP `directory:` overrides.
* Add a **CHANGELOG** entry under the existing subdirectory work.

## Out of scope

* Hard rejection of non-conforming `directory:` (warn-only here; rejection is the follow-up).
* Any change to how the `SPP-PLACEHOLDER` token is substituted downstream — that remains in
  the consuming deploy tooling.
