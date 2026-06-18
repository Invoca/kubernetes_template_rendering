# Reconcile Flag Implementation Plan (OCTO-842)

> **For agentic workers:** Implement task-by-task using TDD. Steps use checkbox (`- [ ]`) syntax for tracking. Write the failing test first, watch it fail, then write minimal code to pass.

**Goal:** Add a `--reconcile` flag to `kubernetes_template_rendering` that replaces the destructive per-entry `rm -rf` prune with a bounded, marker-based sweep: `touch marker → render → delete files older than the marker under the scope root → remove now-empty directories`. This removes the directories of deleted/renamed entries (which `--prune` never did) and eliminates the order-dependent data-loss hazard of `rm -rf` at a prefix root above sibling directories.

**Architecture:** Introduce a stateless-ish `Reconciler` that (1) captures a filesystem marker timestamp before any rendering, (2) validates that rendered output paths stay within their scope prefix (hard-error otherwise), and (3) after all rendering completes, sweeps each scope root by deleting files strictly older than the marker, then removes empty directories bottom-up. The marker is captured **once** in the parent `TemplateDirectoryRenderer#render` (before the fork loop), so it works correctly with the existing `--fork` parallelism: children write fresh files; the parent sweeps after `Process.waitall`. Scope roots and SPP fences are computed from the entries that actually rendered (already filtered by `--cluster_type` / `--region` / `--color`), with `--spp` selecting which `spp/<name>` subtrees are swept.

**Tech Stack:** Ruby, RSpec (existing). No new dependencies.

---

## Dependency: builds on OCTO-840 (`--spp`)

This ticket's scope references `--spp` narrowing and SPP fencing, which are introduced by **OCTO-840** (`origin/OCTO-840_spp_flag`: `--spp` flag, `PlaceholderExpander`, `PLACEHOLDER_TOKEN`). That branch is **not yet on `main`**, and this branch (`OCTO-842_...`) is currently based on `main`.

- [ ] **Task 0: Rebase `OCTO-842_...` onto `OCTO-840_spp_flag`** (or merge OCTO-840 first), so `PlaceholderExpander`, the `--spp` flag, and the per-SPP output structure (`<region>/<type>/<color>/spp/<spp-name>/`) are available. All line references below assume the OCTO-840 state of each file.

If OCTO-840 ships first, rebase onto `main` after it merges.

---

## Behavioral Spec (from the ticket)

**Sweep mechanism (the invocaops timestamp pattern):**
1. Touch a marker file, capture its mtime.
2. Render (each `File.write` produces an mtime newer than the marker; `PlaceholderExpander` copies preserve the just-rendered source mtime, also newer than the marker).
3. Under each **scope root**, delete every regular file whose mtime is strictly older than the marker (i.e. not produced this run = leftover from a deleted/renamed entry).
4. Remove now-empty directories bottom-up.

**Scope roots:**
- **Base root** per rendered `(region, cluster_type, color)`: `<rendered_directory>/<region>/<cluster_type>/<color>/`.
- The `spp/` child of each base root is **fenced out** of the base sweep.
- For each requested `--spp NAME`, an additional scope root `<region>/<cluster_type>/<color>/spp/<spp-name>/` is swept. Non-requested `spp/*` children are never swept (fenced).

**Hard errors:**
- `--reconcile` + `--prune` together ⇒ hard error (mutually exclusive). `--prune` alone keeps the legacy per-entry `rm -rf`. `--reconcile` alone does the bounded sweep instead.
- Any rendered entry whose output path resolves **outside** its scope prefix (full-path or relative `..` escape) ⇒ hard error, before any deletion. (The existing fixture pattern `"../some-cluster/%{plain_region}-render-here"` is exactly this escaping case.)

**Acceptance criteria:**
1. Deleting an entry and re-rendering with `--reconcile` removes its old directory.
2. A single-SPP render touches only that SPP's subtree.
3. Two consecutive identical `--reconcile` renders produce the same deletions (idempotent — the second run deletes nothing).
4. Out-of-prefix paths error.

**Out of scope (Dependencies note):** No standalone GC mode and no `--prune-old-spps`. Deleted-SPP / placeholder-flip cleanup remains a manual `git rm` in the teardown runbook. This is *why* the base sweep fences `spp/` and only sweeps explicitly-requested SPP subtrees.

---

## File Structure

**New:**
- `lib/kubernetes_template_rendering/reconciler.rb` — marker capture, scope validation, sweep, empty-dir removal.
- `spec/kubernetes_template_rendering/reconciler_spec.rb` — unit tests for the reconciler.

**Modified:**
- `lib/kubernetes_template_rendering/cli.rb` — add `--[no-]reconcile`; reject `--reconcile` + `--prune`; thread `reconcile:` into the renderer.
- `lib/kubernetes_template_rendering/cli_arguments.rb` — add `:reconcile` Struct field + `reconcile?`.
- `lib/kubernetes_template_rendering/template_directory_renderer.rb` — capture marker before render, compute scope roots + fences, sweep after `waitall`, thread reconcile state down.
- `lib/kubernetes_template_rendering/resource_set.rb` — expose computed scope roots/fences per `region × color` (incl. SPP roots); validate the entry's output directory is within its base; skip per-entry prune when reconciling.
- `lib/kubernetes_template_rendering/resource.rb` / `deploy_grouped_resource.rb` — validate each written file path stays within the output directory when reconciling.
- `spec/kubernetes_template_rendering/cli_spec.rb` — flag parse + mutual-exclusion error.
- `spec/kubernetes_template_rendering/resource_set_spec.rb` — scope computation + out-of-prefix error.
- `spec/kubernetes_template_rendering/template_directory_renderer_spec.rb` — end-to-end sweep behavior (AC 1–4).
- `README.md`, `CHANGELOG.md`, `lib/kubernetes_template_rendering/version.rb` (bump to `0.4.0`, assuming OCTO-840 lands `0.3.0`).

---

## Task 1: `--reconcile` flag, arg field, and mutual exclusion with `--prune`

**Files:** `cli_arguments.rb`, `cli.rb`, `spec/.../cli_spec.rb`

- [ ] **Step 1: Failing test** — in `cli_spec.rb`:

```ruby
describe "--reconcile flag" do
  before do
    FileUtils.mkdir_p(template_directory_option)
    FileUtils.touch(File.join(template_directory_option, described_class::DEFINITIONS_FILENAME))
  end

  it "parses --reconcile into args" do
    _, args = described_class.send(:parse, [render_option, "--reconcile", template_directory_option])
    expect(args.reconcile?).to be(true)
  end

  it "defaults reconcile to false" do
    _, args = described_class.send(:parse, [render_option, template_directory_option])
    expect(args.reconcile?).to be(false)
  end

  it "hard-errors when --reconcile and --prune are combined" do
    expect {
      described_class.send(:parse, [render_option, "--reconcile", "--prune", template_directory_option])
    }.to raise_error(ArgumentError, /reconcile.*prune.*mutually exclusive/i)
  end
end
```

(Note: `cli_spec.rb` may need the pre-existing `--render-directory=` → `--rendered-directory=` typo fix from OCTO-840 already applied; confirm after rebase.)

- [ ] **Step 2:** Run, confirm failure (no `reconcile?`, no flag, no error).

- [ ] **Step 3:** Add `:reconcile` to the `CLIArguments` Struct field list and a predicate:

```ruby
def reconcile?
  !!reconcile
end
```

- [ ] **Step 4:** In `cli.rb`, add after the `--[no-]prune` option (`cli.rb:34`):

```ruby
op.on("--[no-]reconcile", "bounded post-render sweep (delete files older than marker, prune empty dirs); mutually exclusive with --prune") { args.reconcile = _1 }
```

After `parser.parse!(options)` / `args.template_directory = options.first`:

```ruby
if args.prune? && args.reconcile?
  raise ArgumentError, "--reconcile and --prune are mutually exclusive"
end
```

Thread `reconcile: args.reconcile` into `TemplateDirectoryRenderer.new(...)` in `renderer_from_args`.

- [ ] **Step 5:** Run `cli_spec.rb` — all pass.
- [ ] **Step 6:** Commit: `OCTO-842: add --reconcile flag and reject combining it with --prune`.

---

## Task 2: `Reconciler` — marker, scope validation, sweep, empty-dir removal

**Files:** create `reconciler.rb` + `reconciler_spec.rb`

- [ ] **Step 1: Failing test** — `reconciler_spec.rb` covering:
  - `within_scope!` raises `Reconciler::OutOfScopeError` for a `..`-escaping or absolute path outside the root, and is silent for a path inside the root.
  - `sweep!`: given a root with one fresh file (mtime > marker) and one stale file (mtime < marker), deletes only the stale file, then removes the directory that becomes empty, and **does not** touch files under a fenced child dir.
  - Idempotency: a second `sweep!` over the same (now-clean) tree deletes nothing.

Sketch:

```ruby
require 'tmpdir'
require 'fileutils'
require_relative "../../lib/kubernetes_template_rendering/reconciler"

RSpec.describe KubernetesTemplateRendering::Reconciler do
  let(:root) { Dir.mktmpdir }
  after { FileUtils.rm_rf(root) }

  def write_with_mtime(path, mtime)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    File.utime(mtime, mtime, path)
  end

  it "deletes files older than the marker and removes empty dirs, fencing excluded subtrees" do
    reconciler = described_class.new(root)          # captures marker = now
    base = File.join(root, "us-east-1/staging/orange")
    stale = File.join(base, "deleted-entry/x.yaml")
    fresh = File.join(base, "kept-entry/y.yaml")
    fenced = File.join(base, "spp/qa02a/z.yaml")
    write_with_mtime(stale,  reconciler.marker_mtime - 60)
    write_with_mtime(fresh,  reconciler.marker_mtime + 60)
    write_with_mtime(fenced, reconciler.marker_mtime - 60)   # old but fenced -> survives

    reconciler.sweep!(root: base, fences: [File.join(base, "spp")])

    expect(File.exist?(fresh)).to be(true)
    expect(File.exist?(fenced)).to be(true)
    expect(File.exist?(stale)).to be(false)
    expect(File.exist?(File.dirname(stale))).to be(false)   # emptied dir removed
  end

  it "raises when a path escapes the scope root" do
    reconciler = described_class.new(root)
    expect { reconciler.within_scope!(File.join(root, "../evil"), root) }
      .to raise_error(described_class::OutOfScopeError)
  end
end
```

- [ ] **Step 2:** Run, confirm failure.

- [ ] **Step 3:** Implement `lib/kubernetes_template_rendering/reconciler.rb`:

```ruby
# frozen_string_literal: true

require 'fileutils'

module KubernetesTemplateRendering
  # Bounded, marker-based reconcile sweep. Captures a filesystem marker timestamp at
  # construction; after rendering, deletes files strictly older than the marker under a
  # scope root (skipping fenced subtrees), then removes now-empty directories.
  class Reconciler
    class OutOfScopeError < StandardError; end

    attr_reader :marker_mtime

    def initialize(rendered_directory)
      FileUtils.mkdir_p(rendered_directory)
      @marker_path = File.join(rendered_directory, ".ktr-reconcile-marker-#{Process.pid}")
      FileUtils.touch(@marker_path)
      @marker_mtime = File.mtime(@marker_path)
    end

    # Hard-error if `path` resolves outside `scope_root` (full-path or relative escape).
    def within_scope!(path, scope_root)
      resolved = File.expand_path(path)
      root     = File.expand_path(scope_root)
      unless resolved == root || resolved.start_with?(root + File::SEPARATOR)
        raise OutOfScopeError, "rendered path #{resolved} resolves outside scope prefix #{root}"
      end
    end

    def sweep!(root:, fences: [])
      return unless File.directory?(root)
      fence_set = fences.map { |f| File.expand_path(f) }
      delete_stale_files(root, fence_set)
      remove_empty_dirs(root, fence_set)
    end

    def finish!
      FileUtils.rm_f(@marker_path)
    end

    private

    def delete_stale_files(root, fence_set)
      Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |path|
        next unless File.file?(path)
        next if fenced?(path, fence_set)
        File.delete(path) if File.mtime(path) < @marker_mtime
      end
    end

    def remove_empty_dirs(root, fence_set)
      Dir.glob(File.join(root, "**/"), File::FNM_DOTMATCH)
         .sort_by { |dir| -dir.length } # deepest first
         .each do |dir|
        next if fenced?(dir, fence_set)
        next if File.expand_path(dir) == File.expand_path(root) # keep the swept root itself
        Dir.rmdir(dir) if (Dir.children(dir) rescue []).empty?
      end
    end

    def fenced?(path, fence_set)
      resolved = File.expand_path(path)
      fence_set.any? { |f| resolved == f || resolved.start_with?(f + File::SEPARATOR) }
    end
  end
end
```

Notes:
- Strict `<` comparison keeps files written in the same clock tick as the marker (rendered this run); only truly older leftovers are deleted ⇒ idempotency (AC 3).
- The swept root itself is preserved even if empty, but **deleted-entry subdirectories** under it are removed (AC 1). Whether to also remove a now-empty base root can be decided in Task 4 (recommended: leave the explicitly-rendered base in place, remove deeper emptied dirs).

- [ ] **Step 4:** Run `reconciler_spec.rb` — all pass.
- [ ] **Step 5:** Commit: `OCTO-842: add Reconciler (marker, scope validation, bounded sweep)`.

---

## Task 3: ResourceSet exposes scope roots + fences and validates out-of-prefix

**Files:** `resource_set.rb`, `spec/.../resource_set_spec.rb`

The renderer needs, per rendered `(region, color)` of each entry: the **base scope root** `<rendered_directory>/<region>/<type>/<color>`, the **fence** (`<base>/spp`), and (for placeholder entries) the requested per-SPP roots `<base>/spp/<spp-name>`. ResourceSet already computes the formatted `output_directory`; expose a parallel computation and validate containment.

- [ ] **Step 1: Failing test** — in `resource_set_spec.rb`:
  - `#reconcile_scopes(spps:)` returns one entry per `region × color` with `base_root`, `fences: [<base>/spp]`, and `spp_roots` (only when the entry is a placeholder entry and `spps` is non-empty).
  - When `directory` escapes (`"../some-cluster/%{plain_region}-render-here"`), `reconcile_scopes` raises `Reconciler::OutOfScopeError` (the output directory is not within `<rendered_directory>/<region>/<type>/<color>`).

- [ ] **Step 2:** Run, confirm failure.

- [ ] **Step 3:** Implement. Add a method that mirrors the `render` region/color loop but yields scope metadata instead of rendering:

```ruby
def reconcile_scopes(spps: [])
  @regions.flat_map do |plain_region|
    @colors.map do |c|
      base_root = File.join(@rendered_directory, plain_region, @kubernetes_cluster_type, c)
      output_directory = File.join(@rendered_directory,
        format(@target_output_directory, plain_region: plain_region, color: c, type: @kubernetes_cluster_type))

      # Out-of-prefix guard: the entry's real output dir must live under its base scope.
      Reconciler.within_scope_static!(output_directory, base_root)

      spp_roots =
        if @placeholder_token && spps.any?
          spps.map { |name| File.join(base_root, "spp", name) }
        else
          []
        end

      { base_root: base_root, fences: [File.join(base_root, "spp")], spp_roots: spp_roots }
    end
  end
end
```

Add a class-level helper to `Reconciler` (or reuse an instance) for the static containment check used at planning time:

```ruby
def self.within_scope_static!(path, scope_root)
  resolved = File.expand_path(path)
  root     = File.expand_path(scope_root)
  unless resolved == root || resolved.start_with?(root + File::SEPARATOR)
    raise OutOfScopeError, "entry output #{resolved} resolves outside scope prefix #{root}"
  end
end
```

(Alternatively pass the live `Reconciler` instance down and call `within_scope!`.)

- [ ] **Step 4:** Run `resource_set_spec.rb` — pass.
- [ ] **Step 5:** Commit: `OCTO-842: compute reconcile scope roots/fences and enforce out-of-prefix`.

---

## Task 4: Wire reconcile into TemplateDirectoryRenderer (marker + post-render sweep)

**Files:** `template_directory_renderer.rb`, `spec/.../template_directory_renderer_spec.rb`

- [ ] **Step 1: Failing integration test** (drives AC 1–4 end-to-end against real files in a `Dir.mktmpdir`):

  - **AC 1 (deleted entry):** render two entries under the same base, then re-render with one entry removed from `definitions.yaml` + `--reconcile`; assert the removed entry's directory is gone and the surviving entry's files remain.
  - **AC 2 (single SPP):** with two SPP subtrees on disk, render `--reconcile --spp=qa02a`; assert only `spp/qa02a` is swept and `spp/qa08a` (non-requested) is untouched.
  - **AC 3 (idempotent):** run the identical `--reconcile` render twice; assert the second run deletes nothing (capture file set / mtimes before & after).
  - **AC 4 (out-of-prefix):** an entry whose `directory` escapes the base raises `Reconciler::OutOfScopeError` and performs no deletion.

- [ ] **Step 2:** Run, confirm failure.

- [ ] **Step 3:** Implement in `render`:

```ruby
def render(args)
  reconciler = nil
  scopes = []
  if args.reconcile?
    reconciler = Reconciler.new(@rendered_directory)          # marker BEFORE any write
    scopes = collect_scopes(args)                              # validates out-of-prefix, fail fast
  end

  # ... existing fork/render loop unchanged ...

  if reconciler
    sweep_all(reconciler, scopes)
    reconciler.finish!
  end
end

private

def collect_scopes(args)
  resource_sets.values.flatten.flat_map { |rs| rs.reconcile_scopes(spps: @spps) }
end

def sweep_all(reconciler, scopes)
  # Base roots: sweep once each, fencing spp/.
  scopes.map { |s| [s[:base_root], s[:fences]] }.uniq.each do |base_root, fences|
    reconciler.sweep!(root: base_root, fences: fences)
  end
  # Requested SPP roots: sweep each (no fences).
  scopes.flat_map { |s| s[:spp_roots] }.uniq.each do |spp_root|
    reconciler.sweep!(root: spp_root)
  end
end
```

Key points:
- The marker is captured in the parent **before** the fork loop, so all child writes (and `PlaceholderExpander` copies) are newer than the marker. The sweep runs in the parent **after** `Process.waitall`, avoiding fork races.
- `collect_scopes` runs the out-of-prefix validation up front (before rendering) so AC 4 fails fast with no deletions.
- Base sweep fences `spp/`; only requested `--spp` roots are swept ⇒ AC 2 and the "no `--prune-old-spps`" constraint.

- [ ] **Step 4:** Run the integration spec — AC 1–4 pass.
- [ ] **Step 5:** Commit: `OCTO-842: marker capture + bounded post-render sweep in renderer`.

---

## Task 5: File-level out-of-prefix guard in Resource / DeployGroupedResource

Multi-file (jsonnet) and deploy-grouped templates can emit arbitrary filenames; guard each written path against the output directory when reconciling.

**Files:** `resource.rb`, `deploy_grouped_resource.rb`, `resource_spec.rb`

- [ ] **Step 1: Failing test** — a multi-file template returning a filename containing `../` raises `Reconciler::OutOfScopeError` under `--reconcile` and is unaffected without it.
- [ ] **Step 2:** Run, confirm failure.
- [ ] **Step 3:** In `write_template`, before each `File.write(output_path(name), ...)`, call `Reconciler.within_scope_static!(output_path(name), @output_directory) if args.reconcile?`. (Requires passing `args` into the path-validation point; it is already available in `write_template`.)
- [ ] **Step 4:** Run — pass.
- [ ] **Step 5:** Commit: `OCTO-842: validate per-file output paths stay within scope when reconciling`.

---

## Task 6: Docs, changelog, version

**Files:** `README.md`, `CHANGELOG.md`, `version.rb`

- [ ] Document `--reconcile` in `README.md`: bounded marker sweep, mutually exclusive with `--prune`, scope = `<region>/<cluster_type>/<color>/` (+ requested `spp/<name>` subtrees; non-requested SPP children fenced), removes empty dirs, out-of-prefix paths error. Note no GC mode / no `--prune-old-spps` (deleted-SPP cleanup = manual `git rm`).
- [ ] `CHANGELOG.md` entry under `0.4.0`.
- [ ] Bump `VERSION` to `0.4.0`.
- [ ] Commit: `OCTO-842: document --reconcile, changelog, bump to 0.4.0`.

---

## Verification checklist (maps to AC)

- [ ] `bundle exec rspec` green; `bundle exec rake` (spec + rubocop) green.
- [ ] AC 1 — deleted/renamed entry's old directory removed after `--reconcile` re-render.
- [ ] AC 2 — `--reconcile --spp=X` sweeps only `spp/X`; other `spp/*` untouched.
- [ ] AC 3 — two identical `--reconcile` runs ⇒ identical (zero) deletions on the second.
- [ ] AC 4 — out-of-prefix (e.g. `../some-cluster/...`) ⇒ `OutOfScopeError`, no deletions.
- [ ] `--reconcile --prune` ⇒ hard error.
- [ ] `--reconcile` alone replaces (does not invoke) the legacy per-entry `rm -rf`.
- [ ] No-reconcile, no-prune render output is byte-identical to today.

---

## Design notes / risks

- **mtime vs. `find ! -newer`:** invocaops' shell pattern uses `find ! -newer marker -delete` (mtime ≤ marker). We use strict `<` so files written in the marker's clock tick survive; on sub-second filesystems (APFS/ext4) rendered files are reliably newer. This guarantees idempotency (AC 3).
- **`PlaceholderExpander` mtime preservation:** it copies source mtime to the per-SPP destination. Because the SPP source files are rendered in the same run (mtime > marker), the copies are also > marker and survive the sweep. No special-casing needed.
- **Fork safety:** marker captured pre-fork in the parent; sweep runs post-`waitall` in the parent. Children never sweep.
- **Why fence `spp/` in the base sweep:** the base root contains the `SPP-PLACEHOLDER` intermediate tree and possibly many `spp/<name>` outputs from other runs. Per the Dependencies note there is no SPP GC; sweeping the base must not touch SPP subtrees, so `spp/` is fenced and only explicitly-requested SPP roots are swept.
- **kube-platform / region-less entries:** these render via `normal_render` with no region/color dimension; treat the entry's `output_directory` as its own scope root (no `spp/` fence) if reconcile must support them — confirm during Task 4 whether kube-platform is ever rendered with `--reconcile`.
