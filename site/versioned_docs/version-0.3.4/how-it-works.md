---
id: version-0.3.4-how-it-works
title: How esy works
original_id: how-it-works
---

This document describe esy internals.

## Overview

Almost every esy command operates in context of a [project
sandbox](concepts.md#sandbox) which is defined by a sandbox
[manifest](concepts.md#manifest) (usually `package.json` but `esy.json` is also
supported).

## Pipeline

The typical pipeline from having a clean checkout of an esy project till the
point where all artifacts are built consists of the following steps:

- **Solve Dependencies**

  Produces `esyi.lock.json` out of `package.json`.
  This step is optional as `esyi.lock.json` can be already present in a fresh
  checkout.

- **Fetch Dependencies**

  Ensures all packages mentioned in `esyi.lock.json` is in the [Global
  Installation Cache](#global-installation-cache).

- **Install Dependencies**

  Populates the sandbox's `node_modules` directory.

- **Crawl Package Graph**

  Crawls the sandbox's `node_modules` directory and constructs the `Package.t`
  graph.

- **Produce Task Graph**

  Folds over the `Package.t` graph and produces the `Task.t` graph.

- **Build Task Graph**

  Executes `Task.t` graph which uses `esy-build-package` to build each `Task.t`.


### Solve Dependencies

This step produces a [solution](concepts.md#solution) out of dependency
declarations found in project's root [manifest](concepts.md#manifest) and all
transitively dependent packages' manifests.

First, a package universe (a transitive closure of all dependencies' versions)
is constructed by consulting package registries (npm and opam currently) and
other sources (remote URLs, local paths and various git repositories hostings).

Constructed package universe is then encoded as [CUDF](concepts.md#CUDF) and
then is being fed to a CUDF solver (provided by the `esy-solve-cudf` npm package
which uses [mccs][] solver underneath).

The result of the solver is then decoded and serialized on disk as
`esyi.lock.json` file. It is advised to commit such file to a project's VCS as
it captures the current state of the project's dependencies thus allowing to
reproduce the exact same environment on other hosts at other points in time.

[mccs]: http://www.i3s.unice.fr/~cpjm/misc/mccs.html

Modules of interest:

- `esyi/Universe`
- `esyi/Resolver`
- `esyi/Solver`
- `esyi/Solution`

### Fetch Dependencies

This step consumes a [solution](concepts.md#solution) produced by the previous
[Solve Dependencies](#solve-dependencies) step and ensures that all packages
mentioned in the solution are fetched and cached in the [Global Installation Cache](#global-installation-cache).

How it works:

- Traverse the solution
- For each record of the solution:
  - Fetch source (either a tarball or a git repo or ...)
  - Apply all needed patches
  - Pack as a `*.tgz` and store in a cache

Modules of interest:

- `esyi/Fetch`
- `esyi/FetchStorage`
- `esyi/Solution`

### Install Dependencies

This step consumes a [solution](concepts.md#solution) produced by the 
[Solve Dependencies](#solve-dependencies) step and populates with sandbox's
`node_modules` directory by unpacking `*.tgz` from the [Global Installation
Caches](#global-installation-cache).

Modules of interest:

- `esyi/Fetch`

### Crawl Package Graph

This step crawls the sandbox's `node_modules` directory to construct the
`Package.t` graph.

This graph has package metadata at nodes and edges are instances of dependency
relations between packages. The dependency relation is defined by the following
fields in a package's manifest:

- `"dependencies"`
- `"peerDependencies"` - same as `"dependencies"` from the point of view of `esy`,
  was used by the legacy implementation of `esy install` command to defer
  installing dependencies to the root package.
- `"optDependencies"` - this models optional dependencies (if they are installed
  they are used, otherwise - ignored), an analogue to opam's `depopts` which are
  being discouraged now.

Modules of interest:

- `esy/Package`
- `esy/Sandbox`

### Produce Task Graph

This step consumes a `Package.t` graph and produces a `Task.t` graph.

The resulted graph is topologically isomorphic to the original `Package.t` graph
but contains much more information about the build process for each of the
packages in a sandbox:

- A list of ready to execute commands
- An environment which is needed to execute build commands

Modules of interest:

- `esy/Package`
- `esy/Task`

### Build Task Graph

After `Task.t` is constructed it's time to build it.

Each `Task.t` is serialized into JSON format called [Build
Plan](concepts.md#build-plan) which is then used to invoke `esy-build-package`
executable.

Modules of interest:

- `esy/Build`
- `esy/PackageBuilder`
- `esy-build-package/Builder`

## Caches

There are multiple levels of caches used by esy.

> There's no garbage collection mechanism provided at the moment. This can be a
> problem for hosts with little free disk space available.

### Global Installation Cache

This cache stores source tarballs of concrete package versions.

#### Location & Structure

The default location for the cache is `~/.esy/esyi/tarballs` and can be
indirectly controlled by the `--cache-path` option of `esyi` executable.

```bash
% tree ~/.esy/esyi/tarballs
├── @esy-ocaml
│   ├── esy-installer__0.0.0.tgz
│   └── substs__0.0.1.tgz
├── @opam
│   ├── base-bytes__opam:base__1cf5b511.tgz
...
```

Tarballs are stored in a state which allows them to be extracted directly
inside the `node_modules` directory of a project's sandbox.

#### Cache Key

The cache key used for the cache consists of:

- Package name
- Package version
- Package source (needed if package was fetched not from a registry but a git
  repository or other source)
- A hash of all contents of patches and additional files (if those are defined
  for the package, currently used by the opam overrides infra).

### Global Build Store

This cache stores built artifacts of esy packages and related metadata.

#### Location & Structure

The default location for the cache is `~/.esy/3<prefix>` and can be
indirectly controlled by the `--store-path` option of `esy` executable.

The `<prefix>` part of the path is consist of a number of underscore characters
`_` which pads the store path so that the length of the path to the `ocamlrun`
executable in the store is exactly 128 characters.

> The number 128 comes from the fact that on some systems a path mentioned in a
> shebang line (first line of executable which starts with `#!`) is limited to
> 128 characters. Thus the current limit ensure that OCaml bytecode executables
> can be run from the store.

The padding is needed to allow relocating built artifacts between stores.

The cache looks like:

```bash
% tree ~/.esy/3_*
├── b
│   ├── ocaml-4.6.1-4f6b0960
│   ├── ocaml-4.6.1-4f6b0960.info
│   ├── ocaml-4.6.1-4f6b0960.log
│   ...
├── i
│   ├── ocaml-4.6.1-4f6b0960
│   ...
└── s
```

Where

- `b/<key>` is a directory which is used as a build root for a corresponding
  package.
- `b/<key>.log` is log file for the build process of a package which corresponds
  to the `<key>`.
- `b/<key>.info` contains information about the corresponding build process such
  timer ellapsed and so on.
- `s/<key>` is a stage directory for built artifact installation (packages
  install their own artifacts there and then esy moves `s/<key>` to `i/<key>` so
  that the changes to the store are executed atomically.
- `i/<key>` is an installation directory, this is the directory which hosts
  built artifacts of the package which corresponds to the `<key>`.


#### Cache Key

The cache key used for the cache consists of:

- Package name
- Package version
- Hash of all build/install commands and other esy specific metadata from a
  package manifest
- Hash of all dependencies' cache keys

### Local Build Store

Local Build Store follows exactly the same layout and cache key as the Global
Build Store but it is local to a sandbox and located at
`<sandboxPath>/node_modules/.cache/_esy/store` path.

It is used to store artifacts of packages which don't have a stable build
identity (unreleased software which changes often and doesn't warrant sroting
its artifacts in a Global Build Store).

### Local Sandbox Cache

Local Sandbox Cache stores a computed package and build task graph. It is
located at `<sandboxPath>/node_modules/.cache/_esy/sandbox-<hash>` where
`<hash>` part is a hash of:

- Store Path
- Sandbox Path
- Local Store Path
- Version of esy

The cache is stored in a format readable by OCaml [Marshal][] module.

> Reading the cache file with a version of esy which has different
> `SandboxInfo.t` layout than the one with which the cache was produced with
> usually results in a Segmentation Fault.

[Marshal]: https://caml.inria.fr/pub/docs/manual-ocaml/libref/Marshal.html
