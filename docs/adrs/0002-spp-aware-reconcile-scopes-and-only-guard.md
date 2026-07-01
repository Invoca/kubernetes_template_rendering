# SPP-aware reconcile scopes and a --reconcile/--only guard

* Status: accepted
* Deciders: Kubernetes platform reviewers
* Date: 2026-06-29

Technical Story: OCTO-842 — add a `reconcile` flag to kubernetes_template_rendering / depends on [PR #14](https://github.com/Invoca/kubernetes_template_rendering/pull/14) (`--spp` + `PlaceholderExpander`)

## Context and Problem Statement

[ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md) established `--reconcile`: after rendering the desired resources, sweep each owned root and delete files older than a marker captured before rendering, then remove empty directories. The base case sweeps `<region>/<cluster_type>/<color>/` with an `spp/` fence so the shared base sweep never touches Staging Partial Platform (SPP) subtrees.

SPP definitions render under `<region>/<cluster_type>/<color>/spp/SPP-PLACEHOLDER/...`. The literal `SPP-PLACEHOLDER` token is preserved so it can be expanded per-instance downstream. PR #14 introduces the `--spp NAME` flag and `PlaceholderExpander`, which expands the `SPP-PLACEHOLDER` output into one concrete subtree per requested SPP (e.g. `spp/staging-qa02a/`).

Two questions follow for reconcile:

1. When a deploy targets specific SPPs (`--spp staging-qa02a`), which subtrees may reconcile sweep? It must delete stale files inside the *requested* SPP only, and must never touch `SPP-PLACEHOLDER` or unrequested SPP siblings (deleted-SPP / placeholder-flip cleanup stays a manual `git rm` per the teardown runbook).
2. How should `--reconcile` interact with PR #14's `--only` (render a subset of `definitions.yaml` entries)?

## Decision Drivers

* **Bounded, targeted sweeps** — `--spp` must narrow reconcile to exactly the requested SPP subtrees.
* **No accidental cross-SPP deletion** — `SPP-PLACEHOLDER` and unrequested SPPs must be fenced out of the sweep.
* **No silent data loss from partial renders** — a flag that renders a subset must not let reconcile delete the un-rendered (and therefore stale-looking) siblings.
* **Minimal coupling to PR #14** — OCTO-842 owns reconcile scoping; expansion is PR #14's. Avoid duplicating `PlaceholderExpander` and keep the merge trivial.

## Considered Options

### Flag interaction: `--reconcile` + `--only`

* **Option A — Hard error.** Reject `--reconcile --only` the same way `--reconcile --prune` is rejected.
* **Option B — Narrow the sweep to only the rendered entries' roots.** Sweep just the roots of the `--only` entries.
* **Option C — Allow it as-is.** Run the normal base sweep alongside a subset render.

### `--spp` reconcile scope derivation

* **Option 1 — Substitute requested SPP names into the SPP-PLACEHOLDER sweep root.** For each SPP scope whose root contains `SPP-PLACEHOLDER`, emit one sweep root per requested target (`spp/staging-qa02a`, …); with no `--spp`, sweep `spp/SPP-PLACEHOLDER` as-is.
* **Option 2 — Always sweep the whole `spp/` tree** and rely on mtimes alone.

## Decision Outcome

**Flag interaction: Option A (hard error).** `--reconcile --only` exits with a mutually-exclusive error. `--only` renders a subset, but reconcile sweeps the shared `<region>/<cluster_type>/<color>` base root; the un-rendered siblings would be older than the marker and get deleted. Option C is unsafe (silent deletion of valid resources). Option B is plausible but adds per-entry scoping complexity for a workflow no one has asked for; SPP targeting is already served by `--spp`, which scopes reconcile to per-SPP subtrees. We can revisit Option B if a real need appears.

**`--spp` scope derivation: Option 1 (placeholder substitution).** `collect_reconcile_scopes` splits each entry's sweep root into base roots (non-SPP, swept with an `spp/` fence) and SPP roots. For an SPP root, `spp_reconcile_roots`:

* with no `--spp`, returns the `spp/SPP-PLACEHOLDER` root unchanged (TEST CASE 2 — only the placeholder subtree is swept; expanded instances are left alone);
* with `--spp X [Y…]`, replaces the `SPP-PLACEHOLDER` segment with each requested target, yielding one sweep root per requested SPP (`spp/X`, `spp/Y`).

Each derived root is re-validated to stay within `rendered_directory`. Substitution reuses the existing `ResourceSet::SPP_PLACEHOLDER` constant, so reconcile does **not** depend on PR #14's `PlaceholderExpander`; the two constants are equal once #14 lands.

### Flag interaction summary

| Flags | Reconcile sweep |
| --- | --- |
| `--reconcile` (no `--spp`) | base roots (with `spp/` fence) + `spp/SPP-PLACEHOLDER/` |
| `--reconcile --spp X [Y…]` | base roots (fenced) + one root per requested `spp/X/`, `spp/Y/`; `SPP-PLACEHOLDER` and unrequested SPPs excluded |
| `--reconcile --prune` | hard error |
| `--reconcile --only …` | hard error |

### Positive Consequences

* `--spp` deploys reconcile only the targeted SPP subtree(s); `SPP-PLACEHOLDER` and unrequested SPPs are never swept.
* Reconcile is decoupled from expansion: it sweeps based on on-disk state and mtimes regardless of how files were produced, so it needs no `PlaceholderExpander` dependency.
* The two destructive-combination footguns (`--prune`, `--only`) fail fast with clear messages.

### Negative Consequences

* `--reconcile --only` is unavailable; subset-targeted reconcile must go through `--spp`.
* Deleted-SPP and placeholder-flip cleanup remain manual `git rm` (no GC mode, no `--prune-old-spps`), as scoped in the ticket.

## Implementation Notes

* `lib/kubernetes_template_rendering/cli.rb` — adds `--spp` / `--only` parsing (repeatable, de-duplicated), threads `spps:` into the renderer, and adds the `--reconcile --only` guard.
* `lib/kubernetes_template_rendering/cli_arguments.rb` — adds `:spps`, `:only`.
* `lib/kubernetes_template_rendering/template_directory_renderer.rb` — accepts `spps:`; `collect_reconcile_scopes` calls the new `spp_reconcile_roots` to expand SPP roots per requested target.

### Merge ordering with PR #14

PR #14 should land first; OCTO-842 then rebases onto it. The `--spp` / `--only` flag plumbing, `CLIArguments` fields, and renderer signature here intentionally mirror PR #14 so de-duplication is trivial. Two pieces are deliberately **not** duplicated and are delivered by PR #14: the `--only` *filtering* of rendered entries (here `--only` only feeds the reconcile guard), and `PlaceholderExpander`. After #14 merges, the renderer's `renderer_from_args` call should also pass `only:` for filtering.

## Links

* Refines [ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md)
* Depends on [PR #14](https://github.com/Invoca/kubernetes_template_rendering/pull/14)
