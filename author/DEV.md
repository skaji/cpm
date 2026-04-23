# Development Notes

## Builder Refactor

Current builder classes:

- `App::cpm::Builder::Base`
- `App::cpm::Builder::EUMM`
- `App::cpm::Builder::MB`
- `App::cpm::Builder::Static`

Current selection order in `App::cpm::Worker::Installer`:

1. `Static` (only when `--static-install` is enabled and `x_static_install` is true)
2. `MB`
3. `EUMM`

Current builder interface:

- class methods
  - `supports`
  - `new`
- instance methods
  - `configure`
  - `build`
  - `test`
  - `install`

Notes:

- `new` is intentionally simple. It currently just stores arguments and should not be treated as a fallback point.
- builder fallback is currently based on `supports` and `configure`.
- `Static` is now written in cpm style, but is still based on ideas from `Module::Build::Tiny`.

## Current State Model

`App::cpm::Distribution` currently has these states:

- `registered`
- `deps_registered`
- `resolved`
- `fetched`
- `configured`
- `built`
- `ready`
- `installed`

Current meaning:

- `configured`: builder has been chosen and configure has succeeded
- `built`: build step has completed
- `ready`: the distribution is usable by later stages; this is intended to become the dependency gate
- `installed`: files have been copied to the final target location

## Task Model

Current worker task types:

- `fetch`
- `configure`
- `build`
- `test`
- `install`
- `resolve`

Current source-distribution flow:

1. `fetch`
2. `configure`
3. `build`
4. `test` (unless `--notest`)
5. `ready`
6. `install`

Current prebuilt flow:

1. `fetch`
2. `configured`-equivalent metadata/requirement handling
3. `ready`
4. `install`

Notes:

- prebuilt is currently treated as already-built / already-tested enough to skip `build` and `test`
- this is close to a `--notest` assumption, but conceptually it may be cleaner to think of prebuilt as an already-prepared artifact

## Findings

- `install` should mean only final placement into the target location. It should not also run build/test once those became separate tasks.
- `local_lib` and `install_base` are not the same thing:
  - `install_base` is the target location used by EUMM/MB/static install path generation
  - `local_lib` is also used to construct `PATH` / `PERL5LIB` during configure/build/test/install
- `ready` is a better internal concept than `ready_to_install` for the current design
- user-facing CLI/logging can still say `install`; internal model does not have to

## Suspicious / Incomplete Areas

### 1. Dependency gate is still `installed`

Even though `ready` exists, `App::cpm::Master::is_satisfied` still checks:

- resolved distribution exists
- and that distribution is `installed`

This means `ready` is not yet the dependency gate.

This is the next major behavioral change.

### 2. `build`/`test` environment is not yet derived from dependent distributions' `blib`

The long-term direction is:

- stop depending on partially populated `local/lib` during the build graph
- instead construct `@INC` / `PATH` from distributions that are already `ready`

That is not implemented yet.

### 3. `install` naming may still be misleading

Internally, `install` currently means:

- copy built/prebuilt files to the final destination

Possible future rename candidates discussed:

- `rollout`
- `deploy`

For now, code still uses `install`.

### 4. Prebuilt is not fully modeled as a builder yet

There was discussion of `App::cpm::Builder::Prebuilt`.

Open question:

- should prebuilt become an install-only builder object
- or remain a special path handled in `Worker::Installer`

### 5. `Static` install compatibility

`Static` now uses cpm-controlled behavior. That is fine for cpm's direction, but it is still worth remembering:

- some distributions may assume tool-specific install behavior
- the long-term direction is still to treat such distributions as needing fixes rather than preserving arbitrary install hooks

## Decisions Still Needed

### 1. When to switch the dependency gate from `installed` to `ready`

This is the key next step.

Once this changes:

- dependents can move forward after dependencies are `ready`
- final `install` can be delayed

### 2. How to build `@INC` / `PATH` from `ready` distributions

Likely needs builder/distribution APIs for:

- library paths
- executable/script paths
- maybe blib roots

### 3. Whether final placement should remain mandatory

Carmel-style `rollout` was discussed as an optional final step:

- some environments can run directly from `blib`
- some environments want a single rolled-out directory

cpm still needs its own decision here.

### 4. Whether `install` should later be renamed internally

`ready` already avoids `ready_to_install`.

If final placement becomes optional, `rollout` may be a better internal term than `install`.

## Small History Notes

- `Static` had a bug from the builder-refactor commit where:

  - `sort find_files(...)`

  was parsed as a sort comparator call

- fixed later as:

  - `sort(find_files(...))`

The fix was committed directly on `version-1`.
