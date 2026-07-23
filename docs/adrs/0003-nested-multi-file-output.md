# Nested output directories from MULTI_FILE_RENDER keys containing `/`

* Status: accepted
* Deciders: James Ebentier, Kubernetes platform reviewers
* Date: 2026-07-23

Technical Story: [OCTO-919](https://invoca.atlassian.net/browse/OCTO-919) — nested multi-file output spike (ST-11)

## Context and Problem Statement

Ephemeral deploy scripts (`deploy_ephemeral.sh` in voice-agent, contact-center-agents, polaris) render a flat file set and then shuffle files into `pr-N/{app,mysql}/` directories before committing to the rendered repo. If `MULTI_FILE_RENDER` keys could contain `/` (e.g. `pr-12/app/polaris-svc`), the service-templates-jsonnet library (ST-05) could emit the final layout directly and ST-09's vendored scripts could drop the file shuffle.

Keys are producer-controlled (they come from the template author's Jsonnet). A `/` in a key **currently crashes the render** because `File.write` does not create intermediate directories.

**Key→filename producer** (`lib/kubernetes_template_rendering/jsonnet_template.rb:60-67`):

```ruby
def render_json_doc(json_doc, default_file_name, file_name_to_yaml_hash)
  if multi_file_jsonnet_doc?(json_doc)
    render_multi_file_jsonnet!(json_doc, file_name_to_yaml_hash)
  else
    file_name = file_name_from_object(json_doc, default: default_file_name)
    file_name_to_yaml_hash["#{file_name}.yaml"] = with_auto_generated_yaml_comment(json_doc.to_yaml)
  end
end
```

Keys (and `MULTI_FILE_RENDER_NAME` values, resolved by `file_name_from_object`) pass through **untouched** into the returned hash — no Jsonnet-side change is needed for nested paths.

**File-writing site** (`lib/kubernetes_template_rendering/resource.rb:34-50`):

```ruby
def write_template(args)
  print_status

  # If a Hash is returned, that means this is a multi-file template, meaning we need to iterate over the hash.
  # Else a String is returned and we can write it directly to the output file.
  rt = rendered_template(args)

  if args.render_files?
    if rt.is_a?(Hash)
      rt.each do |filename, contents|
        File.write(output_path(filename), contents)
      end
    else
      File.write(output_path(@output_filename), rt)
    end
  end
end
```

**Path join** (`lib/kubernetes_template_rendering/resource.rb:68-70`):

```ruby
def output_path(filename)
  File.join(@output_directory, filename)
end
```

`File.write` on the joined path is where `Errno::ENOENT` fires for nested keys. This is the single write path for all multi-file output; the non-hash branch's `@output_filename` derives from the template basename and can never contain `/`.

### Executable ENOENT evidence

Before this change, `spec/kubernetes_template_rendering/resource_spec.rb` drove `Resource#render` with a hash key `pr-1/app/foo.yaml` and observed:

```
Errno::ENOENT: No such file or directory @ rb_sysopen - .../pr-1/app/foo.yaml
```

No working template can emit `/`-bearing keys today, so enabling nested keys is not a backward-compatibility break.

## Decision Drivers

* Drop the `pr-N/{app,mysql}` file-shuffle from ephemeral deploy scripts once producers can emit nested keys (ST-05 / ST-09).
* Keys are producer-controlled; the gem should not rewrite or reject `/` in keys beyond path-safety containment.
* Crash today implies zero live consumers of nested keys — safe to enable without a migration.
* Reconcile and prune must remain correct for nested subtrees (marker-based sweep posture from ADR-0001/0002).

## Considered Options

* **Option A — Enable nested keys at the write site with a containment guard.** Add `FileUtils.mkdir_p` before `File.write` and reject `..` escapes in `output_path`.
* **Option B — Keep flat output and the script shuffle.** Document the blocker; pin ENOENT regression spec; no `lib/` change.
* **Option C — Gate nested keys behind a new CLI flag.** Rejected: keys already crash today; a flag adds surface for no safety gain.

## Decision Outcome

Chosen option: **Option A (implement nested output)**, because all four "small" bar conditions are satisfied:

1. **Confined change:** Only `Resource#write_template`, `Resource#output_path`, and `require "fileutils"` in `resource.rb`, plus specs/fixtures. No changes to `cli.rb`, `cli_arguments.rb`, `jsonnet_template.rb`, `resource_set.rb`, `template_directory_renderer.rb`, or `reconciler.rb`.
2. **Suite stability:** Full existing spec suite passes with zero expectation changes to pre-existing examples.
3. **Containment guard:** Four lines in `output_path`, matching `template_directory_renderer.rb:118-124` posture.
4. **Interplay:** `--prune`, `--reconcile`, and SPP expansion require documentation only (see Interplay analysis).

### Positive Consequences

* ST-05 may emit `pr-<prId>/{app,mysql}/...` keys after gem release and ST-01's Gemfile pin bump from `0.6.2`.
* ST-09 scripts can drop the file shuffle once the fleet converges; they are written to tolerate both layouts until then.
* Flat-output consumers (e.g. `cleanup.sh` scanning `pr-*-application.yaml` at the color-folder root) are unaffected until a producer opts in.

### Negative Consequences

* A key `foo` and key `foo/bar` in one template can coexist as `foo.yaml` and `foo/` directory on POSIX — legal, no special handling.
* Nested keys are unusable by ST-05 until (a) this gem version is published to rubygems.org and (b) ST-01's `Gemfile` pin is deliberately bumped.

## Interplay analysis

### `--prune`

`ResourceSet#prune_directory` (`resource_set.rb:248-257`) runs `FileUtils.rm_rf(directory)` on the whole output directory before rendering. Nested subtrees are removed with the parent directory; **no code change required**.

### `--reconcile`

`Reconciler#collect_stale_files` walks with `Find.find(root)` (recursive — nested files are visited). `remove_empty_dirs` globs `File.join(root, "**", "*/")` deepest-first. Freshly written nested files (mtime > marker) survive; stale nested files from removed keys are deleted; emptied nested directories are removed. **No Reconciler change required.**

### SPP expansion

`PlaceholderExpander` already handles nested directories — fixture `spec/fixtures/placeholder_expander/source/SPP-PLACEHOLDER/nested-SPP-PLACEHOLDER/service.yaml` proves rendered trees may nest. **No change required.**

### DeployGroupedResource

`DeployGroupedResource#filename_for_deploy_group` builds flat `<basename>-<group>-deploy.yaml` output filenames. **Unaffected.**

### print_status cosmetics

`Resource#print_status` prints `File.basename(output_path(@output_filename))` — the template's default name, not per-key names. **Non-issue for hash-key nesting.**

## Path safety

`File.join` + `File.write` would follow `..` out of the output directory without a guard (`File.expand_path("dir/../evil", "/base")` → `/base/evil`). `output_path` applies two layers of containment before any write:

1. **Lexical check** — `File.expand_path` on the joined path must stay under the expanded output directory (catches `..` segments and absolute-looking keys after `File.join` neutralization).
2. **Filesystem check** — walk each existing path component from the output directory toward the target file's parent directory; reject if any component is a symlink, and verify the resolved parent directory (via `File.realpath` on existing segments) still lies under the real output directory. This closes a bypass where a committed symlink inside a `*-kubernetes` checkout could let a producer-controlled nested key write outside the render sandbox — `File.expand_path` alone never resolves symlinks.

Absolute-looking keys (`/etc/passwd`) are neutralized by `File.join` semantics (`File.join("dir", "/etc/passwd")` → `"dir/etc/passwd"`) and then subject to the same guards.

**Per-key atomicity:** for multi-file hashes, each key is validated immediately before its own write. A later key that fails containment does not roll back files already written for earlier keys in the same hash.

## Pros and Cons of the Options

### Option A — Enable nested keys at write site

* Good, because change is minimal (~10 lines in one file).
* Good, because Jsonnet producer already passes keys through unchanged.
* Good, because reconcile/prune/SPP already handle nested trees.
* Bad, because gem release + ST-01 pin bump are prerequisites before library adoption.

### Option B — Defer (flat output only)

* Good, because zero gem churn.
* Bad, because ephemeral scripts keep the file shuffle indefinitely.
* Bad, because nested keys remain a footgun (ENOENT) for any author who tries them.

### Option C — CLI flag

* Good, because explicit opt-in.
* Bad, because keys already crash — no producer uses nested keys today.
* Bad, because adds CLI surface and documentation burden for no safety gain over Option A.

## Links

* Depends on [OCTO-918](https://invoca.atlassian.net/browse/OCTO-918) (ST-10) for same-repo sequencing only.
* Consumed by ST-05 (library file-key derivation) and ST-09 (scripts quartet) after gem release.
* Related: [ADR-0001](0001-strict-rendering-paths-for-stale-resource-deletion.md), [ADR-0002](0002-spp-aware-reconcile-scopes-and-only-guard.md)
