# Development Notes

This note summarizes the work after `e01d6db`.

## Goal

The main goal was to stop treating `install` as part of dependency progression.

Concretely:

- move build-system-specific logic into builder classes
- separate `configure`, `build`, `test`, and final `install`
- stop relying on partially populated `local/lib` during the build graph
- let distributions become dependency-ready before final installation
- make final installation a simple last phase

Another intended goal is to narrow what gets finally installed by default.

The intended default is:

- install the direct targets
  - modules given directly to `cpm install ...`
  - modules selected from `cpanfile` / `META.*` / similar direct inputs
- and install only their runtime dependencies

In other words, the final file placement should not necessarily include every distribution that was needed during build/test.

## What Changed

### 1. Builders became the center of build/install behavior

Current builder classes:

- `App::cpm::Builder::Base`
- `App::cpm::Builder::EUMM`
- `App::cpm::Builder::MB`
- `App::cpm::Builder::Static`
- `App::cpm::Builder::Prebuilt`

Builder responsibilities now include:

- `configure`
- `build`
- `test`
- `install`
- reporting built artifact paths via `libs` / `paths`

`Builder::Base` now owns the common install behavior:

- install built files from `blib`
- install `blib/meta`

This means `make install` / `./Build install` are no longer the normal path.

### 2. Worker tasks were split into build phases

The worker task model is now:

- `resolve`
- `fetch`
- `configure`
- `build`
- `test`

`install` is no longer a worker task.

`Worker::Installer` is now focused on:

- fetch / unpack
- builder selection
- running `configure`, `build`, `test`

### 3. Final install became a Master phase

`install` is now a final phase run directly by `App::cpm::Master`.

Meaning:

- build/test graph first
- final file placement later

This was the largest behavioral change in the branch.

### 4. Distribution state was simplified

Current lifecycle state:

- `resolved`
- `fetched`
- `configured`
- `built`
- `tested`
- `installed`

Separate scheduler flags:

- `registered`
- `deps_registered`

Separate graph-derived readiness in `App::cpm::Master`:

- `dependency_ready`

`dependency_ready` means:

- under `--notest`: the distribution is built and its runtime dependency closure is dependency-ready
- under `--test`: the distribution is tested and can be used as a dependency

This replaces the old habit of using `installed` as the only practical dependency gate.

### 5. Scheduler became fixed-point based

Because dependency readiness is derived state, one scheduler pass is not enough.

`App::cpm::Master` now repeatedly adds tasks until no further change occurs.

This is needed for chains like:

- dependency becomes dependency-ready
- that enables another distribution to `build`
- that later enables another distribution to `test`

without requiring another outer `get_task` round just to discover the new tasks.

### 6. Build/test environments come from builders

Builders now expose built artifact paths:

- `libs`
- `paths`

These are based on built output under `blib`, not on final install location.

`Master` computes dependency environments and passes them through tasks.
`Builder::Base` then assembles `PERL5LIB` / `PATH`.

This moved environment assembly into one place instead of splitting it between `Worker` and `Builder`.

### 7. `blib/meta` handling moved into builders

Current rule:

- builder `build` writes `blib/meta`
- builder `install` installs `blib/meta`

Meta creation/install is now gated by `distvname` computed in `Builder::Base->new`.

Important behavior:

- CPAN distributions get `.meta/...`
- git/url installs do not, matching older `version-1` behavior

### 8. Prebuilt flow was made consistent with the new model

Prebuilt is now represented by `App::cpm::Builder::Prebuilt`.

Current prebuilt behavior:

- prebuilt is treated as already built
- scheduler uses it via `dependency_ready`
- final install uses the same builder install path as other builders

### 9. Logging/progress changed to match install-last

Non-verbose terminal success logging now shows:

- `DONE fetch` for prebuilt under `--notest`
- `DONE build` for source distributions under `--notest`
- `DONE test` under `--test`

`DONE install` is no longer the normal non-verbose signal.

Build log still records:

- `Installing distribution`
- `Successfully installed distribution`

Progress output was also adjusted so final install no longer dominates terminal output semantics.

### 10. HTTP backend detection was fixed

Separate from the install-last work, `App::cpm::HTTP` had a bug where the `HTTP::Tiny` backend was not selected correctly.

That was fixed, and it reduced flaky HTTPS fetch behavior seen with `LWP` in some environments.

## Current Shape

The current design is roughly:

1. resolve dependencies
2. fetch sources / prebuilt artifacts
3. configure/build/test through builders
4. mark distributions dependency-ready
5. once the graph is done, perform final install

This is the intended direction of the refactor, and at this point it is implemented end-to-end.

## Resolved Release Issues

### 1. Dependency readiness is now Master-owned

The old `usable` flag has been removed from `Distribution`.
Distribution now keeps lifecycle state only.

Graph-derived readiness now lives in `App::cpm::Master` as `dependency_ready`.

This keeps:

- distribution lifecycle state
- scheduler bookkeeping
- graph-derived dependency readiness

separate enough for the version 1.0.0 model.

### 2. `installed` is final-install bookkeeping

Final install still marks distributions as `installed`, but dependency progression no longer depends on it.
It is used only for final install reporting and failure accounting.

### 3. Final install UX remains separate

With install-last, users may see a long build/test period and only later final placement.

Terminal logging for the final install phase is intentionally left for separate UX work.
The per-distribution `Successfully installed distribution` log remains in `build.log`.

### 4. `CPAN::Meta::Spec` phase rules follow the spec

Build scheduling treats runtime dependencies as prerequisites for the build phase.
This is not ideal from a modeling perspective, but it follows `CPAN::Meta::Spec`.

The current phase gates are:

- configure: `configure`
- build: `configure`, `runtime`, `build`
- test: `configure`, `build`, `runtime`, `test`
- dependency readiness under `--no-test`: `runtime`

### 5. Partial-success final install policy is implemented

If some distributions fail, final install still installs distributions that:

- succeeded far enough to be dependency-ready
- are selected for final installation

The overall `cpm install` command still fails if any selected distribution or resolve step failed.

### 6. Compatibility / escape hatches were added

Two user-facing escape hatches now exist:

- `--use-install-command`: use `make install` / `./Build install` when available, with dependency `PERL5LIB` / `PATH`
- `--install-all`: final-install every dependency-ready distribution

These are mainly for compatibility and transition, not because they are preferred as the long-term default.

### 7. Large prebuilt installs were made fast again

The install-last branch introduced a serious slowdown for large installs.

Benchmark command used during investigation:

```console
rm -rf local && perl -Ilib script/cpm install $(cat ~/modules)
```

Both sides used prebuilt artifacts.

Observed numbers on the test machine:

- `c2ad7fd`: about 18.5 seconds for 858 installed distributions
- install-last branch before optimization: about 205 seconds
- after optimization: about 22 seconds

Two hot spots caused most of the regression.

First, final install called `dependency_env_for($dist, [qw(configure build runtime)])`
for every selected distribution.

That is required only when using build-system install commands such as:

- `make install`
- `./Build install`

Normal final install from `blib`, including prebuilt install, does not need dependency
`PERL5LIB` / `PATH`.

Builders now expose `needs_install_env`.
Only `Builder::EUMM` and `Builder::MB` return true when `--use-install-command`
is enabled.

Second, `_resolved_distribution` repeatedly scanned all distributions while checking
dependency readiness and while building dependency environments.

The result is now cached by package and version range.
The cache is cleared in `add_distribution` whenever the distribution/provides set changes.

Important future rule:

- do not add broad `dependency_env_for` calls to final install unless the install path really needs dependency environment
- if distribution/provides data becomes mutable in another place, clear `_resolved_distribution` there too
- be careful when caching `dependency_env_for` itself, because its result depends on `dependency_ready`

## Summary

The large refactor after `e01d6db` reached its main target:

- builder-driven build pipeline
- install-last execution
- common final installation from built artifacts
- dependency progression based on `dependency_ready`, not `installed`

The remaining work for 1.0.0 is release mechanics and broader verification, not the original architectural change.
