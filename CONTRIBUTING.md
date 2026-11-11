# Contributing

## Set up

Install Salam 0.6.1 or later, a host C compiler, and clone this repository.
The C compiler builds the `sigaction` layout oracle used by `make check`.

## Common tasks

Run these commands from the repository root:

| Command | Purpose |
|---|---|
| `make build` | Compile a consumer of `signal.salam` with the LLVM backend. |
| `make test` | Build and run the test suite with `tests/run.sh`. |
| `make test-llvm` | Build and run the test suite with the LLVM backend. |
| `make format` | Format all Salam sources in place. |
| `make check` | Run format checks, the ABI oracle, build, and tests. |
| `make check-abi` | Compile and run the `sigaction` layout oracle on this host. |
| `make clean` | Remove build output. |

`make check` is the local gate. CI also runs `make test-llvm`.

## Repository layout

- `signal.salam` contains the library.
- `tests/` contains Salam test programs and their expected output files.
- `ci/sigaction_offsets.c` checks `sigaction` field offsets against host headers.
- `ci/windows_compile.salam` checks that the Windows stubs compile.
- `.github/workflows/ci.yml` defines the CI jobs.

## Tests

Each `tests/<name>.salam` program asserts with `std/testing` and ends with
`ret testing.Summary()`. Its stdout must match `tests/<name>.out` byte for
byte. Add both files for each new test. Tests do not read the terminal.

| Environment variable | Purpose | Default |
|---|---|---|
| `SALAM` | Salam compiler executable. | `salam` on `PATH` |
| `SALAM_BACKEND` | Backend passed to the compiler. | Compiler's default backend |
| `TEST_TIMEOUT` | Maximum seconds for each test run. | `30` |

Run one test by name with `tests/run.sh <name>`.

## Code style

- Run `make format`; `salam format` is the formatting authority.
- Use four-space indentation.
- Add the project header and module comment to every source file.
- Put `@en "Name"` immediately before its `///` documentation comment.
- Use `PascalCase` for package-level functions and `snake_case` for methods
  and fields.
- Write source comments and documentation in English.

## Documentation is part of the change

Update the README and affected `///` comments when behavior changes. A doc
comment that contradicts the code is a defect.

## Commits

Use Conventional Commits, such as `docs:`, `fix:`, `feat:`, `refactor:`,
`chore:`, `test:`, or `ci:`. Do not put an issue key in the subject.

## CI

The `check` job runs on `ubuntu-latest` and `macos-latest`; it runs `make check`
and `make test-llvm`. The `windows-compile` job compiles
`ci/windows_compile.salam` and never runs it. The `abi-netbsd`, `abi-freebsd`,
and `abi-openbsd` jobs compile and run the C oracle in a virtual machine. A
Windows-only change has no runtime CI.
