# SPP Derived Base Output Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make SPP definitions render into the derived base path `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`, with `subdirectory:` composing on top, so the SPP token lands in the rendered tree and stays bounded for `--reconcile`.

**Architecture:** SPP-ness is detected by the definition name containing the `SPP-PLACEHOLDER` token — the same signal that already derives `cluster_type = staging`. `TemplateDirectoryRenderer` derives an `spp` boolean from the name and passes it to `ResourceSet`, which selects an SPP base path instead of the standard base when resolving the output directory. The change is additive: non-SPP behavior is unchanged, and `spp:` defaults to `false`.

**Tech Stack:** Ruby, RSpec.

## Global Constraints

- Files start with `# frozen_string_literal: true` (match surrounding files).
- The SPP token literal is `SPP-PLACEHOLDER`, defined once as a constant and referenced everywhere (DRY — it is currently duplicated in `template_directory_renderer.rb`).
- `format(...)` only substitutes `plain_region`/`type`/`color`; the `spp` and `SPP-PLACEHOLDER` path segments are literals that must survive verbatim into the rendered path.
- Warn-only rollout: do NOT raise on a non-conforming `directory:`; the existing deprecation warning is the only enforcement here.
- Run the full suite with `bundle exec rspec`.

---

### Task 1: SPP-aware base path resolution in `ResourceSet`

**Files:**
- Modify: `lib/kubernetes_template_rendering/resource_set.rb`
- Test: `spec/kubernetes_template_rendering/resource_set_spec.rb`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `ResourceSet::SPP_PLACEHOLDER` → `"SPP-PLACEHOLDER"` (String constant).
  - `ResourceSet#initialize(..., spp: false, ...)` — new keyword arg, defaults `false`.
  - For an SPP `ResourceSet`, `#target_output_directory` resolves to `"%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER"` (neither field) or `".../spp/SPP-PLACEHOLDER/<sub>"` (subdirectory only).

- [ ] **Step 1: Write the failing tests**

In `spec/kubernetes_template_rendering/resource_set_spec.rb`, inside the existing `describe "output directory pattern resolution" do` block, update the `subject` and add an `spp_value` let so SPP can be toggled. Replace the existing subject block (currently lines ~54-60) with:

```ruby
    subject(:target_output_directory) do
      described_class.new(config: resolution_config,
                          rendered_directory: rendered_directory,
                          template_directory: template_directory,
                          definitions_path: definitions_path,
                          kubernetes_cluster_type: "prod",
                          spp: spp_value).target_output_directory
    end

    let(:spp_value) { false }
```

Then add these two contexts inside the same `describe "output directory pattern resolution"` block (e.g. just before its closing `end`):

```ruby
    context "for an SPP definition with neither directory nor subdirectory" do
      let(:spp_value) { true }

      it "uses the SPP base path" do
        expect(target_output_directory).to eq("%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER")
      end
    end

    context "for an SPP definition with subdirectory only" do
      let(:spp_value) { true }
      let(:subdirectory_value) { "my-app" }

      it "appends the subdirectory under the SPP base path" do
        expect(target_output_directory).to eq("%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER/my-app")
      end
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/kubernetes_template_rendering/resource_set_spec.rb -e "output directory pattern resolution"`
Expected: FAIL — `ResourceSet#initialize` does not accept the `spp:` keyword (`ArgumentError: unknown keyword: :spp`).

- [ ] **Step 3: Implement SPP base path resolution**

In `lib/kubernetes_template_rendering/resource_set.rb`:

(a) Add the `spp:` keyword to `initialize` (default `false`) and assign `@spp` **before** `@target_output_directory` is resolved. The relevant portion of `initialize` becomes:

```ruby
    def initialize(config:, template_directory:, rendered_directory:, definitions_path:, kubernetes_cluster_type:, spp: false, variable_overrides: {}, source_repo: nil)
      @spp                     = spp
      @variables               = config["variables"] || {}
      @deploy_group_config     = config["deploy_groups"]
      @omitted_resources       = config["omitted_resources"]
      @template_directory      = template_directory
      @target_output_directory = resolve_target_output_directory(config["directory"], config["subdirectory"])
```

(Leave the remaining lines of `initialize` unchanged.)

(b) Add the SPP constants next to `BASE_OUTPUT_DIRECTORY` (replace the existing `BASE_OUTPUT_DIRECTORY = ...` line):

```ruby
    SPP_PLACEHOLDER = "SPP-PLACEHOLDER"
    BASE_OUTPUT_DIRECTORY = File.join("%{plain_region}", "%{type}", "%{color}")
    # SPP definitions render under an extra spp/SPP-PLACEHOLDER segment so each SPP
    # instance has a distinct, bounded path and the literal token survives for
    # downstream per-instance substitution.
    SPP_BASE_OUTPUT_DIRECTORY = File.join(BASE_OUTPUT_DIRECTORY, "spp", SPP_PLACEHOLDER)
```

(c) Replace the two `BASE_OUTPUT_DIRECTORY` references in `resolve_target_output_directory` with the `base_output_directory` helper, and add the helper. The method becomes:

```ruby
    def resolve_target_output_directory(directory, subdirectory)
      if directory && subdirectory
        raise ArgumentError, "specify only one of 'directory:' or 'subdirectory:' in #{({ 'directory' => directory, 'subdirectory' => subdirectory }).inspect}"
      elsif directory
        warn_directory_deprecated(directory)
        directory
      elsif subdirectory
        File.join(base_output_directory, subdirectory)
      else
        base_output_directory
      end
    end

    # SPP definitions render under SPP_BASE_OUTPUT_DIRECTORY; everything else uses the standard base.
    def base_output_directory
      @spp ? SPP_BASE_OUTPUT_DIRECTORY : BASE_OUTPUT_DIRECTORY
    end
```

(d) Update the resolution doc comment directly above `BASE_OUTPUT_DIRECTORY` (the block currently ending `#   both              -> ArgumentError`) to add the SPP base:

```ruby
    #   neither           -> base path; "%{plain_region}/%{type}/%{color}", or the SPP base
    #                        "%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER" for SPP definitions
    #   both              -> ArgumentError
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/kubernetes_template_rendering/resource_set_spec.rb`
Expected: PASS (new SPP contexts pass; all pre-existing `ResourceSet` examples still pass because `spp:` defaults to `false`).

- [ ] **Step 5: Commit**

```bash
git add lib/kubernetes_template_rendering/resource_set.rb spec/kubernetes_template_rendering/resource_set_spec.rb
git commit -m "Add SPP-derived base output path to ResourceSet"
```

---

### Task 2: SPP-aware `directory:` deprecation warning

**Files:**
- Modify: `lib/kubernetes_template_rendering/resource_set.rb`
- Test: `spec/kubernetes_template_rendering/resource_set_spec.rb`

**Interfaces:**
- Consumes: `ResourceSet#base_output_directory` and the `spp:` keyword from Task 1.
- Produces: for an SPP `ResourceSet` that uses `directory:`, the deprecation warning names the SPP base layout (`%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`) instead of the plain base.

- [ ] **Step 1: Write the failing test**

In `spec/kubernetes_template_rendering/resource_set_spec.rb`, inside the existing `describe "directory deprecation warning" do` block, add `spp: spp_value` to its subject's `described_class.new(...)` call and a default `let`. Update that subject so the constructor call reads:

```ruby
      described_class.new(config: warning_config,
                          rendered_directory: rendered_directory,
                          template_directory: template_directory,
                          definitions_path: definitions_path,
                          kubernetes_cluster_type: "prod",
                          spp: spp_value)
```

and add directly below the existing `let(:subdirectory_value) { nil }` in that block:

```ruby
    let(:spp_value) { false }
```

Then add this context inside the same `describe "directory deprecation warning"` block:

```ruby
    context "when directory is used by an SPP definition" do
      let(:spp_value) { true }
      let(:directory_value) { "custom/spp-path" }

      it "suggests the SPP base layout" do
        expect(warnings).to include("spp/SPP-PLACEHOLDER")
      end
    end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/kubernetes_template_rendering/resource_set_spec.rb -e "SPP definition"`
Expected: FAIL — the warning still names the plain base path, so it does not include `"spp/SPP-PLACEHOLDER"`.

- [ ] **Step 3: Make the warning SPP-aware**

In `lib/kubernetes_template_rendering/resource_set.rb`, change `warn_directory_deprecated` to interpolate `base_output_directory` instead of the `BASE_OUTPUT_DIRECTORY` constant:

```ruby
    def warn_directory_deprecated(directory)
      puts Color.brown("WARNING: #{@template_directory}: `directory:` is deprecated. " \
                       "Remove it to render into the standard #{base_output_directory} layout, " \
                       "or use `subdirectory:` instead. (got `directory: #{directory}`)")
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/kubernetes_template_rendering/resource_set_spec.rb -e "deprecation warning"`
Expected: PASS — the new SPP context passes and the existing non-SPP warning contexts (which only assert the `` `directory:` is deprecated `` substring) still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/kubernetes_template_rendering/resource_set.rb spec/kubernetes_template_rendering/resource_set_spec.rb
git commit -m "Point directory deprecation warning at SPP base layout for SPP definitions"
```

---

### Task 3: Thread the `spp` flag through `TemplateDirectoryRenderer`

**Files:**
- Modify: `lib/kubernetes_template_rendering/template_directory_renderer.rb`
- Test: `spec/kubernetes_template_rendering/template_directory_renderer_spec.rb`

**Interfaces:**
- Consumes: `ResourceSet::SPP_PLACEHOLDER` and the `ResourceSet.new(..., spp:)` keyword from Task 1.
- Produces: `TemplateDirectoryRenderer` passes `spp: name.include?(ResourceSet::SPP_PLACEHOLDER)` to `ResourceSet.new` — `true` for `SPP-PLACEHOLDER` / `SPP-PLACEHOLDER.eu`, `false` otherwise.

- [ ] **Step 1: Update the failing test**

In `spec/kubernetes_template_rendering/template_directory_renderer_spec.rb`, replace the data-driven table header (currently the line beginning `{ "test": "test", ... }.each do |resource_definition_name, expected_kubernetes_cluster_type|`) and the `ResourceSet.new` expectation so the table also asserts the `spp:` flag.

Replace the iteration header with:

```ruby
  {
    "test"               => { cluster_type: "test",    spp: false },
    "prod.gcp"           => { cluster_type: "prod",    spp: false },
    "SPP-PLACEHOLDER"    => { cluster_type: "staging", spp: true },
    "SPP-PLACEHOLDER.eu" => { cluster_type: "staging", spp: true }
  }.each do |resource_definition_name, expected|
```

Within that block, change the cluster-type reference and add `spp:` to the `.with(...)` matcher. The `ResourceSet.new` expectation becomes:

```ruby
      expect(KubernetesTemplateRendering::ResourceSet).to(
        receive(:new)
          .with(
            config: expected_config,
            rendered_directory: rendered_directory,
            template_directory: template_directory,
            definitions_path: definitions_path,
            kubernetes_cluster_type: expected[:cluster_type],
            spp: expected[:spp],
            variable_overrides: {},
            source_repo: nil
          )
          .and_return(resource_set)
      )
```

(`resource_definition_name` is still used unchanged when building the definition.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/kubernetes_template_rendering/template_directory_renderer_spec.rb`
Expected: FAIL — `ResourceSet.new` is called without the `spp:` keyword, so the `.with(...)` matcher does not match.

- [ ] **Step 3: Derive and pass `spp`**

In `lib/kubernetes_template_rendering/template_directory_renderer.rb`, in `resource_sets`, derive `spp` next to `kubernetes_cluster_type` and pass it to `ResourceSet.new`. Use the shared constant in both places. The body of the `config.map` block becomes:

```ruby
        config.map do |name, config|
          next if omitted_names.include?(name)

          kubernetes_cluster_type = name.sub(ResourceSet::SPP_PLACEHOLDER, 'staging').sub(/\..*/, '') # prod.gcp => prod
          spp = name.include?(ResourceSet::SPP_PLACEHOLDER)

          hash[name] ||= []
          hash[name] << ResourceSet.new(
            config: config,
            template_directory: dir,
            rendered_directory: @rendered_directory,
            kubernetes_cluster_type: kubernetes_cluster_type,
            spp: spp,
            definitions_path: definitions_path,
            variable_overrides: @variable_overrides,
            source_repo: @source_repo
          )
        end
```

Also update the duplicate token in `load_config` to use the constant (replace the one `name.sub('SPP-PLACEHOLDER', 'staging')` occurrence there):

```ruby
        if !cluster_type || cluster_type == name.sub(ResourceSet::SPP_PLACEHOLDER, 'staging').sub(/\..*/, '') # prod.gcp => prod
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/kubernetes_template_rendering/template_directory_renderer_spec.rb`
Expected: PASS — all four table rows assert the correct `spp:` flag.

- [ ] **Step 5: Run the full suite**

Run: `bundle exec rspec`
Expected: PASS — all examples green.

- [ ] **Step 6: Commit**

```bash
git add lib/kubernetes_template_rendering/template_directory_renderer.rb spec/kubernetes_template_rendering/template_directory_renderer_spec.rb
git commit -m "Derive and pass spp flag from definition name to ResourceSet"
```

---

### Task 4: Documentation — ADR, CHANGELOG, version bump

**Files:**
- Modify: `docs/adrs/0001-strict-rendering-paths-for-stale-resource-deletion.md`
- Modify: `CHANGELOG.md`
- Modify: `lib/kubernetes_template_rendering/version.rb`

**Interfaces:**
- Consumes: the behavior from Tasks 1-3.
- Produces: docs describing the SPP base path; version `0.5.0`.

- [ ] **Step 1: Update ADR-0001**

In `docs/adrs/0001-strict-rendering-paths-for-stale-resource-deletion.md`, add an SPP row to the resolution table (the table whose rows are `directory only` / `subdirectory only` / `neither` / `both`). Insert this row immediately after the `subdirectory only` row:

```markdown
| `subdirectory` only, SPP definition | `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER/<subdirectory>` |
| neither, SPP definition | `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER` |
```

Then, immediately after the paragraph that begins "`subdirectory:` is a plain literal final segment…", add:

```markdown
Definitions whose name contains the `SPP-PLACEHOLDER` token (the same token from
which the `staging` cluster type is derived) render under an additional
`spp/SPP-PLACEHOLDER` segment: their base path is
`%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`, and `subdirectory:` composes
on top of it. The `spp/SPP-PLACEHOLDER` segment is literal (not substituted by
`format`), so the token survives into the rendered tree for downstream per-instance
substitution while remaining bounded under the `region/type/color` tree. The
warn-only-then-reject rollout for non-conforming `directory:` applies equally to SPP
definitions.
```

- [ ] **Step 2: Add a CHANGELOG entry and bump the version**

In `CHANGELOG.md`, add a new section directly above the `## [0.4.0] - 2026-06-25` heading:

```markdown
## [0.5.0] - 2026-06-26
### Added
- SPP definitions (those whose name contains the `SPP-PLACEHOLDER` token) now render under a derived base path `%{plain_region}/%{type}/%{color}/spp/SPP-PLACEHOLDER`, with `subdirectory:` composing on top. This keeps each SPP instance's output distinct and bounded under the `region/type/color` tree for `--reconcile`, and preserves the literal `SPP-PLACEHOLDER` token for downstream per-instance substitution. The `directory:` deprecation warning now points SPP definitions at the SPP base layout. See ADR-0001.

```

In `lib/kubernetes_template_rendering/version.rb`, bump the version:

```ruby
  VERSION = "0.5.0"
```

- [ ] **Step 3: Verify the suite is still green**

Run: `bundle exec rspec`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add docs/adrs/0001-strict-rendering-paths-for-stale-resource-deletion.md CHANGELOG.md lib/kubernetes_template_rendering/version.rb
git commit -m "Document SPP base path: ADR-0001, CHANGELOG, version 0.5.0"
```

---

## Notes for the implementer

- **Why `spp:` defaults to `false`:** keeps Task 1 independently shippable — `ResourceSet` works correctly before `TemplateDirectoryRenderer` (Task 3) starts passing the flag.
- **Why a shared constant:** the `SPP-PLACEHOLDER` literal previously appeared twice in `template_directory_renderer.rb` and now also in the output path. One constant (`ResourceSet::SPP_PLACEHOLDER`) keeps them in lockstep.
- **`.eu` and other suffixes:** a `.`-suffix only distinguishes the definition entry / its regions and is stripped for cluster-type derivation. `name.include?(SPP_PLACEHOLDER)` still returns `true` for `SPP-PLACEHOLDER.eu`, and the path segment stays the literal `SPP-PLACEHOLDER`; region differentiation comes from `%{plain_region}`.
- **Warn-only:** no task raises on a non-conforming `directory:`. Hard rejection is the documented follow-up in ADR-0001.
