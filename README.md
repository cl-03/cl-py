# cl-py

cl-py is a Common Lisp-first project for exposing high-quality Python open source libraries to
Common Lisp users through explicit, reproducible adapter boundaries.

## Current Status

This repository currently contains:

- A project constitution and Speckit workflow templates
- A Common Lisp code skeleton with an adapter registry
- A development CLI
- A first demonstration adapter for the Python `packaging` library

The current goal is not to hide Python. The goal is to make Python dependencies consumable from a
stable Common Lisp surface.

## Repository Layout

```text
cl-py/
├── cl-py.asd
├── cl-py-tests.asd
├── README.md
├── scripts/
│   ├── dev-cli.lisp
│   └── run-tests.lisp
├── src/
│   ├── package.lisp
│   ├── conditions.lisp
│   ├── process.lisp
│   ├── registry.lisp
│   ├── adapter.lisp
│   ├── cli.lisp
│   └── adapters/
│       └── packaging.lisp
└── tests/
    └── smoke.lisp
```

## Requirements

- Common Lisp implementation: SBCL first
- ASDF available
- Python 3 available on `PATH` or via `CL_PY_PYTHON`
- For the demo adapter: Python package `packaging`

Install the demo Python dependency with:

```bash
python -m pip install packaging
```

## Development CLI

Run the development CLI with SBCL:

```bash
sbcl --script scripts/dev-cli.lisp registry
sbcl --script scripts/dev-cli.lisp packaging metadata
sbcl --script scripts/dev-cli.lisp packaging normalize-version 1.0rc1
```

If Python is not on `PATH`, set:

```bash
CL_PY_PYTHON=/path/to/python
```

## Test Runner

Run the smoke tests with:

```bash
sbcl --script scripts/run-tests.lisp
```

The smoke suite verifies the registry and CLI surface. The `packaging` integration test is skipped
automatically if the dependency is unavailable.

## First Adapter: packaging

The first adapter targets the Python `packaging` project because it is:

- High quality and broadly used
- Small enough to demonstrate the adapter boundary cleanly
- Useful for version normalization and compatibility work inside a wider adapter registry

Current capabilities:

- Discover adapter metadata
- Discover installed upstream module version
- Normalize a version string through `packaging.version.Version`

## Next Steps

- Add adapter manifests instead of hard-coded registry entries
- Add reproducible Python environment bootstrap scripts
- Add more adapters for selected Python libraries
- Add CI to exercise adapter compatibility contracts
