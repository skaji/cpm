# Development Notes

This note summarizes the work after `e01d6db`.

## Goal

The main goal was to stop treating `install` as part of dependency progression.

Concretely:

- move build-system-specific logic into builder classes
- separate `configure`, `build`, `test`, and final `install`
- stop relying on partially populated `local/lib` during the build graph
- let distributions become usable before final installation
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

Separate derived flag:

- `usable`

`usable` means:

- under `--notest`: the distribution is built and its dependency closure is usable
- under `--test`: the distribution is tested and its dependency closure is usable

This replaces the old habit of using `installed` as the only practical dependency gate.

### 5. Scheduler became fixed-point based

Because `usable` is derived state, one scheduler pass is not enough.

`App::cpm::Master` now repeatedly adds tasks until no further change occurs.

This is needed for chains like:

- dependency becomes `usable`
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
- scheduler uses it via `usable`
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
4. mark distributions `usable`
5. once the graph is done, perform final install

This is the intended direction of the refactor, and at this point it is implemented end-to-end.

## Remaining Issues

### 1. `usable` is a practical compromise, not a perfect model

`usable` lives on `Distribution`, but it is not a pure lifecycle state.
It is derived from the dependency graph.

This is workable, but it still mixes:

- self state
- graph-derived readiness

more than ideal.

### 2. `installed` still exists mostly for bookkeeping

Final install still marks distributions as `installed`, and some reporting/failure paths still use that.

This is acceptable for now, but it is no longer the conceptual center of dependency progression.

### 3. Final install UX can still improve

With install-last, users may see a long build/test period and only later final placement.

That is conceptually correct, but terminal UX may still need refinement.

Desired work here:

- revisit terminal logging
- make the install phase easier to understand while it is waiting for build/test to finish
- make the final install phase easier to understand when it starts

### 4. `CPAN::Meta::Spec` phase rules still deserve review

The current code was changed to follow the spec more closely, especially around cumulative phase requirements.

However, the requirement that `runtime` deps are considered before `build` still looks questionable from a modeling perspective and may deserve an upstream issue/discussion.

### 5. Partial-success final install policy is still open

Current install-last behavior does not try to preserve the old “install whatever already succeeded along the way” behavior.

This is deliberate for now, but the policy is still open if practical use suggests a different tradeoff.

The current desired direction is:

- if some distributions fail, still install the distributions that have succeeded and are selected for final installation
- but the overall `cpm install` command should still be treated as failed

### 6. Compatibility / escape hatches still need work

This branch changed behavior in large ways.

User-facing escape hatches are still wanted:

- an option to do install via `make install` / `./Build install`
- an option to install everything as before, not only direct targets plus runtime dependencies

These are mainly for compatibility and transition, not because they are preferred as the long-term default.

## Summary

The large refactor after `e01d6db` reached its main target:

- builder-driven build pipeline
- install-last execution
- common final installation from built artifacts
- dependency progression based on `usable`, not `installed`

The remaining work is mostly refinement, cleanup, and policy, not the original architectural change.
