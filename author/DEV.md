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

`App::cpm::Distribution` currently has one lifecycle state plus scheduler flags.

Lifecycle state:

- `resolved`
- `fetched`
- `configured`
- `built`
- `tested`
- `installed`

Scheduler flags:

- `registered`
- `deps_registered`

Current meaning:

- `resolved`: the distribution is known but nothing has been fetched yet
- `fetched`: source distribution has been fetched and unpacked
- `configured`: source distribution has finished `configure`
- `built`: build artifact exists
- `tested`: test task has completed successfully
- `installed`: files have been copied to the final target location

Scheduler flags mean:

- `registered`: the next task for the current lifecycle state has already been enqueued
- `deps_registered`: dependency resolution needed to leave the current lifecycle state has already been enqueued

When lifecycle state changes, both scheduler flags are reset.

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
5. `install`

Current prebuilt flow:

1. `fetch`
2. `built`
3. `install`

Notes:

- prebuilt is modeled as an already-built artifact
- prebuilt ignores `configure` and `build` requirements
- prebuilt currently stores `test` and `runtime` requirements from `blib/meta/MYMETA.json`, but the scheduler only uses `runtime`
- `--notest` is now a `Master` concern; `Worker` does not receive `notest`

## Findings

- `install` should mean only final placement into the target location. It should not also run build/test once those became separate tasks.
- `local_lib` and `install_base` are not the same thing:
  - `install_base` is the target location used by EUMM/MB/static install path generation
  - `local_lib` is also used to construct `PATH` / `PERL5LIB` during configure/build/test/install
- user-facing CLI/logging can still say `install`; internal model does not have to

## Suspicious / Incomplete Areas

### 1. Dependency gate is still `installed`

`App::cpm::Master::is_satisfied` still checks:

- resolved distribution exists
- and that distribution is `installed`

This is the next major behavioral change.

### 2. `build`/`test` environment is not yet derived from dependent distributions' `blib`

The long-term direction is:

- stop depending on partially populated `local/lib` during the build graph
- instead construct `@INC` / `PATH` from distributions that are already build-usable

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

### 1. When to switch the dependency gate from `installed` to some non-installed state

This is the key next step.

Once this changes:

- dependents can move forward after dependencies are available without final placement
- final `install` can be delayed

### 2. What the non-installed dependency gate should be

Possible choices:

- `built`
- `tested`
- a separate usability state

The current code intentionally does not decide this yet.

### 3. How to build `@INC` / `PATH` from non-installed distributions

Likely needs builder/distribution APIs for:

- library paths
- executable/script paths
- maybe blib roots

### 4. Whether final placement should remain mandatory

Carmel-style `rollout` was discussed as an optional final step:

- some environments can run directly from `blib`
- some environments want a single rolled-out directory

cpm still needs its own decision here.

### 5. Whether `install` should later be renamed internally

If final placement becomes optional, `rollout` may be a better internal term than `install`.

## Small History Notes

- `Static` had a bug from the builder-refactor commit where:

  - `sort find_files(...)`

  was parsed as a sort comparator call

- fixed later as:

  - `sort(find_files(...))`

The fix was committed directly on `version-1`.
