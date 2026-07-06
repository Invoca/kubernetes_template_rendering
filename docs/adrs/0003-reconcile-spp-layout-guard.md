# Enforce the SPP output layout under --reconcile

* Status: accepted
* Deciders: Tristan Starck, Kubernetes platform reviewers
* Date: 2026-07-06

Technical Story: OCTO-842 — add a `reconcile` flag to kubernetes_template_rendering / refines [ADR-0002](0002-spp-aware-reconcile-scopes-and-only-guard.md)

## Context and Problem Statement

[ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md) and [ADR-0002](0002-spp-aware-reconcile-scopes-and-only-guard.md) established `--reconcile` and its SPP-aware sweep scoping. Both rely on Staging Partial Platform (SPP) resources living at the canonical path `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/…`: the base sweep fences out `spp/`, and the SPP sweep substitutes requested targets into the `SPP-PLACEHOLDER` segment. If an SPP entry rendered somewhere else — or a non-SPP entry rendered *under* `spp/` — those scoping assumptions silently break and the sweep can delete the wrong files or miss stale ones.

Nothing enforced that layout. An entry is classified as SPP purely by its `definitions.yaml` key name containing the literal `SPP-PLACEHOLDER` token. The output path is guaranteed to be canonical only for entries using `subdirectory:` or no directory config (they derive `SPP_BASE_OUTPUT_DIRECTORY`). The deprecated `directory:` escape hatch returns its pattern verbatim, ignores the SPP flag, and only prints a warning — so an SPP entry could render anywhere, and a non-SPP entry could be smuggled under `spp/`.

## Decision Drivers

* **Sweep correctness** — reconcile's fence-and-substitute scoping is only sound if SPP resources are exactly where it expects them.
* **Fail fast, before writes** — a layout violation should abort before the marker is captured and before any file is written or deleted.
* **Don't break existing configs needlessly** — a `directory:` override that still lands on the canonical prefix is fine; only genuinely off-layout paths should error.
* **Minimal blast radius** — the guard is a reconcile concern; plain renders (which never sweep) should be unaffected.

## Considered Options

### When to enforce

* **Option A — Only under `--reconcile`.** The layout only matters for the sweep; plain renders are untouched.
* **Option B — Always.** Enforce on every render regardless of `--reconcile`.

### What to enforce

* **Option 1 — Both directions.** SPP entries must be under `spp/SPP-PLACEHOLDER/`; non-SPP entries must not be under any `spp/` segment.
* **Option 2 — Forward only.** Only check that SPP entries are under the canonical prefix.

### How to treat the deprecated `directory:` escape hatch

* **Option X — Validate shape.** Allow `directory:` if it still resolves to the canonical SPP prefix; error otherwise.
* **Option Y — Reject outright.** Under `--reconcile`, any SPP entry using `directory:` is an error.

## Decision Outcome

**Enforce only under `--reconcile` (Option A), in both directions (Option 1), validating shape rather than banning `directory:` (Option X).**

The guard runs in `TemplateDirectoryRenderer#collect_reconcile_scopes` — already the reconcile-only, pre-render validation pass that also checks scope escapes — so a violation raises `Reconciler::SppLayoutError` before `Reconciler.new` captures the marker and before any writes. Plain renders never call it.

`ResourceSet#reconcile_scopes` now carries two extra fields per scope: `spp:` (the entry's SPP flag) and `spp_base_root:` (the canonical `<rendered>/<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER` prefix for that region × color, built from the shared `ResourceSet::SPP_BASE_OUTPUT_DIRECTORY` constant). `validate_spp_layout!` then checks:

* **SPP entry** — `output_directory` must equal `spp_base_root` or sit beneath it (`start_with?(base + File::SEPARATOR)`). The separator guard prevents a sibling like `SPP-PLACEHOLDER-2` from passing on a raw prefix match.
* **Non-SPP entry** — `output_directory` must not contain any `spp` path segment, reusing the existing `within_spp_subtree?` helper.

Comparing against the fully-formatted canonical prefix (rather than counting path segments) keeps the check correct even if a region value ever contains a slash. Because SPP expansion (`PlaceholderExpander`, per ADR-0002 / PR #14) derives its per-target subtrees from this same already-validated `SPP-PLACEHOLDER` root, validating the pre-expansion path is sufficient — `--reconcile --spp` needs no additional check.

### Flag / layout interaction summary

| Situation (under `--reconcile`) | Result |
| --- | --- |
| SPP entry under `…/spp/SPP-PLACEHOLDER/…` (derived or conforming `directory:`) | allowed |
| SPP entry rendering outside that prefix | `SppLayoutError` before any writes |
| Non-SPP entry rendering under any `spp/` segment | `SppLayoutError` before any writes |
| Any of the above without `--reconcile` | guard does not run; renders as before |

### Positive Consequences

* Reconcile's fence-and-substitute scoping (ADR-0002) now rests on an enforced invariant rather than a convention.
* Off-layout SPP configs fail fast with a clear message and delete nothing.
* The deprecated `directory:` hatch stays usable for conforming paths; no forced migration.

### Negative Consequences

* A `directory:`-based SPP layout that reviewers previously tolerated will now hard-error under `--reconcile` and must be moved onto the canonical prefix.
* SPP classification is still name-based (`SPP-PLACEHOLDER` in the entry key); this ADR enforces the *path*, not how SPP-ness is decided.

## Implementation Notes

* `lib/kubernetes_template_rendering/resource_set.rb` — `reconcile_scopes` adds `spp:` and `spp_base_root:`.
* `lib/kubernetes_template_rendering/reconciler.rb` — adds `Reconciler::SppLayoutError`.
* `lib/kubernetes_template_rendering/template_directory_renderer.rb` — adds `validate_spp_layout!`, called from `collect_reconcile_scopes` after the existing scope-escape pass.
* Design/spec: `docs/superpowers/specs/2026-07-06-reconcile-spp-layout-guard-design.md`.

## Links

* Refines [ADR-0002](0002-spp-aware-reconcile-scopes-and-only-guard.md)
* Refines [ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md)
