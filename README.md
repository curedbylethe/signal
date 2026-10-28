# signal

POSIX signal primitives for the [Salam](https://github.com/SalamLang/Salam)
programming language: general POSIX signal sets plus the `SIGWINCH` listening
plumbing extracted from
[basalam](https://github.com/curedbylethe/basalam)'s resize watcher.

The package owns the process-wide handler and the blocked signal mask, and
nothing else: no terminal state, no policy, no widget code.

> **Status: early development.** The signal-set API shipped in `v0.1.1`; the
> disposition API (`Install`, `Restore`, `CurrentMask`) is unreleased on `main`.
> Hardening is tracked separately.

## Install

You need the Salam compiler, version 0.5.9 or later:

```sh
{ curl -fsSL https://raw.githubusercontent.com/SalamLang/Salam/refs/heads/main/install.sh || wget -qO- https://raw.githubusercontent.com/SalamLang/Salam/refs/heads/main/install.sh; } | sh
```

Add signal with Salam's package manager:

```sh
salam add github.com/curedbylethe/signal@v0.1.1
```

## Usage

### SIGWINCH

```salam
import mem

import "github.com/curedbylethe/signal"

func main:
    if not signal.WinchSupported():
        ret
    end

    // Install snapshots the disposition and the mask, gives SIGWINCH its
    // handler, then blocks it: a signal blocked while its disposition is still
    // SIG_DFL would be discarded at generation on Darwin, so the order is the
    // function's job, not the caller's.
    prev := signal.InstallWinchHandler()
    defer mem.Free(prev)
    defer signal.Restore(signal.WinchSignal, prev)

    set := signal.NewWinchSet()
    defer mem.Free(set)

    mut watching := true
    until not watching:
        if signal.WaitWinch(set) == 0:
            watching = false
        else:
            println "the terminal may have resized"
        end
    end
end
```

A handler passed to `Install` runs on the thread that took the signal, so it
may call async-signal-safe functions only: no allocation, no locks, no stdio,
no calls into the Salam runtime. Touching only `volatile sig_atomic_t`,
lock-free atomics or read-only data is safe. It must also save `errno` on
entry and restore it before returning. `InstallWinchHandler` supplies the
package's no-op handler, which meets the contract by doing nothing.

### Signal sets

```salam
import mem

import "github.com/curedbylethe/signal"

func main:
    set := signal.NewSet()
    defer mem.Free(set)

    _ := signal.AddSignal(set, signal.WinchSignal)
    _ := signal.AddSignal(set, 15) // SIGTERM

    if signal.IsSignal(set, 15):
        _ := signal.Block(set)
        // A sigwait on the set now covers both signals.
        _ := signal.Unblock(set)
    end
end
```

## API

### SIGWINCH

| Name | Purpose |
|---|---|
| `WinchSignal` | The `SIGWINCH` number, 28 on macOS and Linux |
| `WinchSupported` | True on POSIX, false on the Windows stub surface |
| `NewWinchSet` | Allocate a caller-owned signal set holding only `SIGWINCH` |
| `Install` | Save the previous disposition and mask, install `handler`, block `sig`; returns a caller-owned handle |
| `InstallWinchHandler` | Install the package no-op handler and block; returns the previous disposition |
| `BlockWinch` | Add `SIGWINCH` to the calling thread's mask; false on Windows or when the call failed |
| `WaitWinch` | Park until `SIGWINCH` is queued, return its number, or 0 |
| `WakeWinch` | Send `SIGWINCH` to this process to break the wait; false on Windows or when the call failed |
| `Restore` | Put a saved disposition and mask back; false when the handle is null or a step failed, and safe to call twice |

`Install` takes a handler of your own: pass `&handler`, and that handler owes
the async-signal-safety contract above. Hand the returned handle to `Restore`
on the way out and release it with `mem.Free`.

### Signal sets

| Name | Purpose |
|---|---|
| `SignalSetSize` | Bytes in a platform signal set: 4 on macOS and OpenBSD, 16 on FreeBSD and NetBSD, 128 on Linux, 0 on Windows |
| `NewSet` | Allocate an empty caller-owned set |
| `FillSet` | Add every signal to a set |
| `AddSignal` | Add one signal number; false when the number is invalid or unsupported |
| `DelSignal` | Remove one signal number; false when the number is invalid or unsupported |
| `IsSignal` | True when the set contains the number |
| `Block` | Block every signal in the set on the calling thread; false when `set` is null or the mask could not be changed |
| `Unblock` | Unblock every signal in the set on the calling thread; false when `set` is null or the mask could not be changed |
| `SetMask` | Replace the calling thread's mask with the set; false when `set` is null or the mask could not be changed |
| `CurrentMask` | Copy of the calling thread's mask; caller frees |

Every POSIX target installs the disposition through `sigaction`, never
`signal()`: Darwin, Linux, FreeBSD, NetBSD and OpenBSD. The `struct sigaction`
is a zeroed block written through per-target offsets inside `signal.salam`;
only `SA_RESTART` is set and `sa_mask` stays empty, so a syscall interrupted by
a delivered signal restarts. `ci/sigaction_offsets.c` proves those offsets with
`_Static_assert`s against each platform's real headers and a `sigaction` round
trip, and CI runs it in a job per BSD. Salam has no BSD port, so the BSD
branches are proven by that oracle and reviewed, not compiled by this package.

CI builds and tests this package on macOS and Linux only; the Windows surface
is a stub and no job compiles it, and DragonFly is not a Salam target. The
signal-set API is part of `v0.1.1`.

## Contributing

`make check` runs the format check, the build, and the test suite locally. It
also compiles and runs the `sigaction` layout oracle in `ci/`, so it needs a
host C compiler; `make check-abi` runs just that step. `make test-llvm` runs the
same tests with the LLVM backend. CI runs both on ubuntu and macos.

## License

GPL-3.0-or-later, the same license family as Salam itself. See
[LICENSE](LICENSE).
