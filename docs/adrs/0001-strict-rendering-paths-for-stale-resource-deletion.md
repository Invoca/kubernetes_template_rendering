# Strict, derived output paths so stale rendered resources can be safely reconciled

* Status: accepted
* Deciders: Tristan Starck, Kubernetes platform reviewers (via PR #17)
* Date: 2026-06-25

Technical Story: OCTO-849 — add a `subdirectory` option to `definitions.yaml` / [PR #17](https://github.com/Invoca/kubernetes_template_rendering/pull/17)

## Context and Problem Statement

The renderer writes Kubernetes manifests into a `rendered_directory`. We want it to remove *stale* resources — those that are no longer rendered — so the rendered tree always matches the current templates. The current `--prune` flag does this bluntly: it `rm_rf`s an output directory before re-rendering. That is destructive (it deletes everything, then re-creates whatever is still rendered) and is only as safe as the output path is correct — a wrong or tree-escaping path means deleting the wrong files.

We are moving to a `--reconcile` flag instead: after rendering the desired set of resources, reconcile compares the rendered output tree against that desired set and deletes only the entries that are no longer rendered. Reconciliation is only safe and correct if the renderer knows exactly which paths it owns and can enumerate the complete desired set within a bounded tree.

Today the output location of each resource set is a freeform `directory:` pattern in `definitions.yaml` that can point anywhere, including escaping the rendered tree via `..` (e.g. `../some-cluster/...`). When output paths are arbitrary, the set of directories the renderer owns is not well-defined, so reconcile cannot safely decide what is stale. How do we make rendering deterministic enough to reconcile reliably — deleting resources that are no longer rendered, and nothing else?

## Decision Drivers

* **Safe reconciliation of stale resources** — the core motivation: `--reconcile` must delete only resources the renderer owns and no longer renders.
* **Deterministic, bounded output paths** — output must be predictable and rooted inside the rendered tree, never escaping it, so the owned set is enumerable.
* **Lower boilerplate** — the `%{plain_region}/%{type}/%{color}` prefix is repeated in nearly every definition.
* **Backward compatibility** — existing `definitions.yaml` files that use `directory:` must keep working.
* **Hard to misuse** — the common case should require the least configuration and offer the fewest footguns.

## Considered Options

* **Option 1 — Strict, derived paths.** Output is always `%{plain_region}/%{type}/%{color}[/<subdirectory>]`. Introduce a `subdirectory:` field, make the prefix the default, and deprecate/restrict the freeform `directory:` field.
* **Option 2 — Keep freeform `directory:` only.** Status quo; document conventions but enforce nothing.
* **Option 3 — Freeform `directory:` plus a rendered-path manifest.** Keep arbitrary layouts but emit an out-of-band manifest of rendered paths that `--reconcile` consults.

## Decision Outcome

Chosen option: **Option 1 — strict, derived output paths.**

Rendered output paths MUST be derived from `plain_region`, the kubernetes cluster type (`type`), and `color`. The output directory of a resource set is resolved from the mutually-exclusive `directory:` and `subdirectory:` fields:

| Config present | Resulting output-directory pattern |
|---|---|
| `directory` only | the `directory` value, verbatim (legacy / escape hatch) |
| `subdirectory` only | `%{plain_region}/%{type}/%{color}/<subdirectory>` |
| `subdirectory` only, SPP definition | `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER/<subdirectory>` |
| neither, SPP definition | `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER` |
| neither | `%{plain_region}/%{type}/%{color}` (base path) |
| both | error (`ArgumentError`) |

`subdirectory:` is a plain literal final segment appended to the base path — no `%{...}` interpolation is performed on the value itself. The resolved pattern still flows through the existing per-region/color `format(...)` step, so e.g. `subdirectory: my-app` with region `us-east-1`, cluster type `prod`, and color `orange` renders into `us-east-1/prod/orange/my-app`. When neither field is given, output goes to the base path (previously a missing `directory:` raised an error).

Definitions whose name contains the `SPP-PLACEHOLDER` token (the same token from
which the `staging` cluster type is derived) render under an additional
`spp/SPP-PLACEHOLDER` segment: their base path is
`%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`, and `subdirectory:` composes
on top of it. The `spp/SPP-PLACEHOLDER` segment is literal (not substituted by
`format`), so the token survives into the rendered tree for downstream per-instance
substitution while remaining bounded under the `region/type/color` tree. The
warn-only-then-reject rollout for non-conforming `directory:` applies equally to SPP
definitions.

Because the base-path and `subdirectory` outputs are deterministic and rooted under the `region/type/color` tree, the renderer owns a predictable, enumerable set of directories. That is the property that lets `--reconcile` compute the desired set, diff it against what is on disk, and delete only the stale entries — safely and without escaping the tree.

Additionally, the freeform `directory:` field is **deprecated**. It remains supported for backward compatibility, but it is the only way to produce a non-conforming (or tree-escaping) path, so new definitions should use `subdirectory:` or the base-path default. As a first step, the renderer now **warns on any use of `directory:`**, suggesting authors remove it (to render into the standard `%{plain_region}/%{type}/%{color}` layout) or switch to `subdirectory:`. A subsequent follow-up will upgrade this to hard validation/removal so that legacy usage cannot break reconcile safety. **(Rejection not yet enforced — currently warn-only.)**

### Positive Consequences

* `--reconcile` can safely delete stale resources because the renderer's output directories are deterministic and bounded.
* Less boilerplate — the common `region/type/color` prefix is supplied automatically.
* The misconfiguration surface shrinks over time as `directory:` usage is retired.

### Negative Consequences

* **Behavior change:** a missing `directory:` no longer raises; it now renders to the base path. The previous "missing `directory:`" error is gone.
* Use of `directory:` is currently only a warning, not an error, so until the follow-up hard validation lands the reconcile-safety guarantee is not yet airtight.
* Deprecating `directory:` requires migrating existing definitions over time.

## Pros and Cons of the Options

### Option 1 — Strict, derived paths (chosen)

* Good, because deterministic, bounded paths make `--reconcile` / stale-resource deletion safe.
* Good, because it removes the repeated `region/type/color` prefix boilerplate.
* Good, because it is backward compatible — `directory:` still works while we steer toward strict paths.
* Bad, because the full guarantee is deferred until `directory:` is validated/retired.

### Option 2 — Keep freeform `directory:` only

* Good, because no migration is required and layouts stay maximally flexible.
* Bad, because output ownership is undefined, so reconcile cannot safely decide what is stale.
* Bad, because patterns can escape the rendered tree via `..`.

### Option 3 — Freeform `directory:` plus a rendered-path manifest

* Good, because it decouples reconcile from path layout and could track arbitrary layouts.
* Bad, because it adds a stateful artifact to generate, store, and trust.
* Bad, because it is more moving parts than simply enforcing a deterministic layout.

## Links

* Implemented by [PR #17](https://github.com/Invoca/kubernetes_template_rendering/pull/17) (OCTO-849) — `subdirectory:` field, base-path default, `ResourceSet` directory resolution.
* Supersedes the implementation spec previously at `docs/superpowers/specs/2026-06-25-subdirectory-option-design.md` (removed; its content is folded into this ADR).
