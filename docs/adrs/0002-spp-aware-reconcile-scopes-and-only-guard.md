# SPP-aware reconcile scopes, layout guard, and a --reconcile/--only guard

* Status: accepted
* Deciders: Tristan Starck, Kubernetes platform reviewers
* Date: 2026-06-29 (revised 2026-07-06)

Technical Story: OCTO-842 — add a `reconcile` flag to kubernetes_template_rendering / depends on [PR #14](https://github.com/Invoca/kubernetes_template_rendering/pull/14) (`--spp` + `PlaceholderExpander`)

## Revision History

* **2026-06-29** — original decision: SPP-aware sweep scopes (placeholder substitution) and the `--reconcile`/`--only` hard-error guard.
* **2026-07-06** — revised the `--spp` sweep scope to *also* sweep `SPP-PLACEHOLDER` (see "`--spp` reconcile scope derivation" below), and folded in the SPP layout guard previously drafted as ADR-0003.

## Context and Problem Statement

[ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md) established `--reconcile`: after rendering the desired resources, sweep each owned root and delete files older than a marker captured before rendering, then remove empty directories. The base case sweeps `<region>/<cluster_type>/<color>/` with an `spp/` fence so the shared base sweep never touches Staging Partial Platform (SPP) subtrees.

SPP definitions render under `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/...`. The literal `SPP-PLACEHOLDER` token is preserved so it can be expanded per-instance downstream. PR #14 introduces the `--spp NAME` flag and `PlaceholderExpander`, which expands the `SPP-PLACEHOLDER` output into one concrete subtree per requested SPP (e.g. `spp/staging-qa02a/`). Crucially, `SPP-PLACEHOLDER` is *always* re-rendered on every run — it is the source `PlaceholderExpander` copies from — so its freshly rendered files are always newer than the reconcile marker.

Three questions follow for reconcile:

1. When a deploy targets specific SPPs (`--spp staging-qa02a`), which subtrees may reconcile sweep? It must delete stale files inside the *requested* SPP and inside `SPP-PLACEHOLDER` (both re-rendered this run), and must never touch unrequested SPP siblings (their deleted-SPP cleanup stays a manual `git rm` per the teardown runbook).
2. How should `--reconcile` interact with PR #14's `--only` (render a subset of `definitions.yaml` entries)?
3. How do we guarantee SPP resources actually land at the canonical `spp/SPP-PLACEHOLDER/` layout the sweep scoping depends on?

## Decision Drivers

* **Bounded, targeted sweeps** — `--spp` must scope reconcile to exactly the subtrees rendered this run.
* **No accidental cross-SPP deletion** — unrequested SPP siblings must be fenced out of the sweep.
* **Sweep the leftovers we own** — `SPP-PLACEHOLDER` is re-rendered every run, so its stale files (from deleted/renamed templates) must be collected, not left to accumulate.
* **No silent data loss from partial renders** — a flag that renders a subset must not let reconcile delete the un-rendered (and therefore stale-looking) siblings.
* **Enforce the layout the sweep assumes** — SPP resources must be where the fence-and-substitute scoping expects them.
* **Minimal coupling to PR #14** — OCTO-842 owns reconcile scoping; expansion is PR #14's. Avoid duplicating `PlaceholderExpander` and keep the merge trivial.

## Considered Options

### Flag interaction: `--reconcile` + `--only`

* **Option A — Hard error.** Reject `--reconcile --only` the same way `--reconcile --prune` is rejected.
* **Option B — Narrow the sweep to only the rendered entries' roots.** Sweep just the roots of the `--only` entries.
* **Option C — Allow it as-is.** Run the normal base sweep alongside a subset render.

### `--spp` reconcile scope derivation

* **Option 1 — Sweep `SPP-PLACEHOLDER` plus one root per requested target.** For each SPP scope whose root contains `SPP-PLACEHOLDER`, sweep the placeholder root itself *and* emit one sweep root per requested target (`spp/staging-qa02a`, …); with no `--spp`, sweep `spp/SPP-PLACEHOLDER` as-is.
* **Option 1a (original, superseded) — Substitute only, excluding `SPP-PLACEHOLDER`.** Under `--spp`, sweep *only* the requested targets and leave `SPP-PLACEHOLDER` untouched.
* **Option 2 — Always sweep the whole `spp/` tree** and rely on mtimes alone.

### SPP layout enforcement (folded from ADR-0003)

* **When:** (A) only under `--reconcile`, or (B) always.
* **What:** (1) both directions — SPP entries must be under `spp/SPP-PLACEHOLDER/`, non-SPP entries must not be under any `spp/` segment; or (2) forward only.
* **`directory:` escape hatch:** (X) allow if it still resolves to the canonical prefix; or (Y) reject outright for SPP entries.

## Decision Outcome

**Flag interaction: Option A (hard error).** `--reconcile --only` exits with a mutually-exclusive error. `--only` renders a subset, but reconcile sweeps the shared `<region>/<cluster_type>/<color>` base root; the un-rendered siblings would be older than the marker and get deleted. Option C is unsafe (silent deletion of valid resources). Option B is plausible but adds per-entry scoping complexity for a workflow no one has asked for; SPP targeting is already served by `--spp`. We can revisit Option B if a real need appears.

**`--spp` scope derivation: Option 1 (sweep `SPP-PLACEHOLDER` plus requested targets).** `collect_reconcile_scopes` splits each entry's sweep root into base roots (non-SPP, swept with an `spp/` fence) and SPP roots. For an SPP root, `spp_reconcile_roots`:

* with no `--spp`, returns the `spp/SPP-PLACEHOLDER` root unchanged (only the placeholder subtree is swept; expanded instances are left alone);
* with `--spp X [Y…]`, returns the `spp/SPP-PLACEHOLDER` root **and** one root per requested target (`spp/X`, `spp/Y`), replacing the `SPP-PLACEHOLDER` segment for each target.

The original decision (Option 1a) excluded `SPP-PLACEHOLDER` under `--spp`. That was revised on 2026-07-06: because the pipeline re-renders `SPP-PLACEHOLDER` on every run before expanding it, its fresh files are always newer than the marker, so sweeping it is marker-safe and *necessary* — otherwise stale output from deleted/renamed templates accumulates in `SPP-PLACEHOLDER` indefinitely when a team only ever deploys with `--spp`. Unrequested SPP siblings are *not* re-rendered this run, so they remain excluded (sweeping them would delete valid current files). Each derived root is re-validated to stay within `rendered_directory`. Substitution reuses the existing `ResourceSet::SPP_PLACEHOLDER` constant, so reconcile does **not** depend on PR #14's `PlaceholderExpander`; the two constants are equal once #14 lands.

**SPP layout enforcement: only under `--reconcile` (A), both directions (1), validate shape (X).** The fence-and-substitute scoping above is only sound if SPP resources live at the canonical `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/` layout. Nothing guaranteed this: SPP-ness is decided by the entry name containing `SPP-PLACEHOLDER`, and the deprecated `directory:` escape hatch can render anywhere while only printing a warning. So under `--reconcile`, `validate_spp_layout!` (run in `collect_reconcile_scopes`, before the marker and any writes) enforces:

* **SPP entry** — `output_directory` must equal the canonical `spp_base_root` (`<rendered>/<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER`) or sit beneath it (`start_with?(base + File::SEPARATOR)`; the separator guards against `SPP-PLACEHOLDER-2`-style prefix collisions).
* **Non-SPP entry** — `output_directory` must not contain any `spp` path segment (reusing `within_spp_subtree?`).

A `directory:` override that still resolves to the canonical prefix is allowed; anything else raises `Reconciler::SppLayoutError` before rendering. Comparing against the fully-formatted canonical prefix (rather than counting path segments) stays correct even if a region value contains a slash. Because expansion derives its per-target subtrees from the already-validated `SPP-PLACEHOLDER` root, validating the pre-expansion path is sufficient — `--reconcile --spp` needs no extra check. Enforcing only under `--reconcile` (Option A) keeps plain renders, which never sweep, unaffected.

### Flag / layout interaction summary

| Flags | Reconcile sweep |
| --- | --- |
| `--reconcile` (no `--spp`) | base roots (with `spp/` fence) + `spp/SPP-PLACEHOLDER/` |
| `--reconcile --spp X [Y…]` | base roots (fenced) + `spp/SPP-PLACEHOLDER/` + one root per requested `spp/X/`, `spp/Y/`; unrequested SPPs excluded |
| `--reconcile --prune` | hard error |
| `--reconcile --only …` | hard error |
| SPP entry rendering outside `spp/SPP-PLACEHOLDER/` (under `--reconcile`) | `SppLayoutError` before any writes |
| non-SPP entry rendering under any `spp/` segment (under `--reconcile`) | `SppLayoutError` before any writes |

### Positive Consequences

* `--spp` deploys reconcile the targeted SPP subtree(s) **and** `SPP-PLACEHOLDER`, so stale template output no longer accumulates in the placeholder tree; unrequested SPPs are never swept.
* Reconcile is decoupled from expansion: it sweeps based on on-disk state and mtimes regardless of how files were produced, so it needs no `PlaceholderExpander` dependency.
* The fence-and-substitute scoping rests on an enforced layout invariant rather than a convention.
* The two destructive-combination footguns (`--prune`, `--only`) fail fast with clear messages.

### Negative Consequences

* `--reconcile --only` is unavailable; subset-targeted reconcile must go through `--spp`.
* Deleted-SPP cleanup for *unrequested* siblings, and placeholder-flip cleanup, remain manual `git rm` (no GC mode, no `--prune-old-spps`), as scoped in the ticket.
* A `directory:`-based SPP layout that reviewers previously tolerated now hard-errors under `--reconcile` and must move onto the canonical prefix.

## Implementation Notes

* `lib/kubernetes_template_rendering/cli.rb` — adds `--spp` / `--only` parsing (repeatable, de-duplicated), threads `spps:` into the renderer, and adds the `--reconcile --only` guard.
* `lib/kubernetes_template_rendering/cli_arguments.rb` — adds `:spps`, `:only`.
* `lib/kubernetes_template_rendering/resource_set.rb` — accepts `spps:`; `reconcile_scopes` carries `spp:` and the canonical `spp_base_root:` per scope.
* `lib/kubernetes_template_rendering/reconciler.rb` — adds `Reconciler::SppLayoutError`.
* `lib/kubernetes_template_rendering/template_directory_renderer.rb` — `collect_reconcile_scopes` calls `spp_reconcile_roots` (SPP-PLACEHOLDER + requested targets) and `validate_spp_layout!` (after the existing scope-escape pass).

### Merge ordering with PR #14

PR #14 landed on `main` first and OCTO-842 was merged on top of it. The `--spp` / `--only` flag plumbing, `CLIArguments` fields, and renderer signature were intentionally mirrored from PR #14, so the merge de-duplicated cleanly (identical hunks). Two pieces are owned by PR #14 rather than this change: the `--only` *filtering* of rendered entries (this ADR only adds the `--reconcile` + `--only` guard) and `PlaceholderExpander` (this change reuses the existing `ResourceSet::SPP_PLACEHOLDER` constant for sweep-root substitution and depends on the expander only at runtime). Since `--spp` expansion now runs during render (`PlaceholderExpander` preserves source mtimes), a `--spp` reconcile is a true end-to-end flow: expanded per-SPP files land after the marker and survive, while stale files in `SPP-PLACEHOLDER` and the requested SPP subtree are swept.

## Links

* Refines [ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md)
* Supersedes the standalone ADR-0003 draft (SPP layout guard), now folded into this record.
* Depends on [PR #14](https://github.com/Invoca/kubernetes_template_rendering/pull/14)
* Design/spec: `docs/superpowers/specs/2026-07-06-reconcile-spp-layout-guard-design.md`
