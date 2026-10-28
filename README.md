# signal

POSIX signal primitives for the [Salam](https://github.com/SalamLang/Salam)
programming language: general POSIX signal sets plus the `SIGWINCH` listening
plumbing extracted from
[basalam](https://github.com/curedbylethe/basalam)'s resize watcher.

The package owns the process-wide handler and the blocked signal mask, and
nothing else: no terminal state, no policy, no widget code.

> **Status: early development.** `v0.1.1` shipped the signal-set API. The
> disposition and wait API (`Install`, `Restore`, `Wait`, `WaitTimeout`) is on
> `main` and unreleased; Windows is a documented stub. Hardening is tracked
> separately.

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

    // The out-block is caller-owned and written on arrival only, so its
    // previous value survives every other status. 4 bytes hold the i32 number.
    out := mem.AllocateZeroed(4 as u64)
    if out == null: ret end
    defer mem.Free(out)

    // Branch on the status, not on the signal number: 0 from WaitTimeout means
    // the bound expired, and only that.
    mut running := true
    until running:
        status := signal.WaitTimeout(set, out, 500)
        if status == signal.WaitArrived:
            // out[0] holds the signal number, not the size: re-read the size.
            println "the terminal may have resized"
        else if status == signal.WaitTimedOut:
            // Nothing arrived inside the bound, so the loop gets control back
            // without another thread having to wake it.
            println "nothing arrived in 500 ms"
        else:
            // WaitBusy, WaitInvalid or WaitFailed: nothing was waited on, so
            // stop instead of spinning on a broken wait.
            running = false
        end
    end
end
```

`WaitWinch` is the same wait specialised to `SIGWINCH`: it takes the set and
returns the signal number on arrival, `WaitInvalid` (`-1`), `WaitFailed`
(`-2`) or `WaitBusy` (`-3`) otherwise, and `0` on Windows only, where there is
no `SIGWINCH`. Never compare a wait against `0` to test whether it worked: `0`
means "timed out" from `WaitTimeout` and "Windows" from `WaitWinch`, and `Wait`
never returns it.

A handler passed to `Install` runs on the thread that took the signal, so it
may call async-signal-safe functions only: no allocation, no locks, no stdio,
no calls into the Salam runtime. Touching only `volatile sig_atomic_t`,
lock-free atomics or read-only data is safe. It must also save `errno` on
entry and restore it before returning. `InstallWinchHandler` supplies the
package's no-op handler, which meets the contract by doing nothing. `Wait` and
`WaitTimeout` allocate nothing at all: the registry, the Darwin kqueue and the
timespec buffer are all built by `Install`.

`Install`, `Restore` and the waits share one process-wide owner: the first
install of a handler does the work, a later install of the same handler only
refcounts, and a later install of a *different* handler is refused with null —
a handler that never runs is the failure this package exists to prevent. Each
`Install` returns a caller-owned copy, so both consumers can free what they
were given; the last `Restore` puts the disposition and the mask back. One
waiter at a time, too: a second concurrent `Wait` or `WaitTimeout` returns
`WaitBusy` rather than silently receiving a subset of the deliveries, so a
consumer retries instead of splitting them.

### Windows

Windows has no `SIGWINCH` and no `sigset_t`, so the surface is a documented
stub: `WinchSupported()` is false, `Wait` and `WaitTimeout` return
`WaitInvalid` (`-1`) without waiting, `Install` returns null, `Restore`
returns false, the set functions return null or fail, and `WaitWinch` returns
`0`. Every function is still safe to call, so the same consumer compiles
there. A consumer that wants resizes on Windows keeps polling the terminal
size — `sys.Size()` or `term.Size()` — every 20 ms instead of installing a
handler.

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
| `Install` | Capture the disposition and mask, install `handler`, block `sig`; installs once and refcounts after that, refuses a different handler with null, and returns a caller-owned handle |
| `InstallWinchHandler` | Install the package no-op handler and block; returns a caller-owned copy of the previous state |
| `BlockWinch` | Add `SIGWINCH` to the calling thread's mask; false on Windows or when the call failed |
| `Wait` | Park until a signal in the set is queued; write its number to `out` and return `WaitArrived`, or `WaitInvalid`, `WaitFailed` or `WaitBusy`; never times out |
| `WaitTimeout` | `Wait` with a bound in milliseconds: `WaitTimedOut` when the bound wins and `out` untouched, `millis` 0 probes once, negative is `WaitInvalid`; one signal per call on Darwin, any set on Linux, `WaitInvalid` on the other POSIX targets |
| `WaitWinch` | Park until `SIGWINCH` is queued and return its number, or a negative status; `0` on Windows only |
| `WakeWinch` | Send `SIGWINCH` to this process to break the wait; false on Windows or when the call failed |
| `Restore` | Put a saved disposition and mask back: above one reference only the calling thread's mask, at the last reference both, and after that the same state again without touching a count; false when the handle is null or a step failed |

### Wait status

| Name | Value | Meaning |
|---|---|---|
| `WaitArrived` | `1` | A signal from the set arrived; `out` holds its number |
| `WaitTimedOut` | `0` | The bound expired and `out` was not written; only `WaitTimeout` returns it |
| `WaitInvalid` | `-1` | A bad argument, a target with no bounded wait, or Windows; nothing was waited on |
| `WaitFailed` | `-2` | The wait itself failed; `out` is untouched |
| `WaitBusy` | `-3` | Another thread in this process already owns the wait; nothing was waited on |

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

CI builds and tests this package on macOS and Linux with both backends. The
`windows-compile` job builds `ci/windows_compile.salam` on `windows-latest` and
never runs it: it names every public symbol so a Windows body that reached for
a POSIX extern fails to compile. That job proves the stub compiles, not that it
waits. DragonFly is not a Salam target. The signal-set API is part of
`v0.1.1`.

## Contributing

`make check` runs the format check, the build, and the test suite locally. It
also compiles and runs the `sigaction` layout oracle in `ci/`, so it needs a
host C compiler; `make check-abi` runs just that step. `make test-llvm` runs the
same tests with the LLVM backend. CI runs both on ubuntu and macos.

Four rules this repository enforces:

1. `salam format` is the authority. `make check` fails on unformatted source,
   so run `make format` rather than hand-wrapping.
2. Four-space indent and 100 columns, including comments; the formatter
   enforces both and CI checks them.
3. Commit messages are Conventional Commits: `feat:`, `fix:`, `test:`, `ci:`,
   `docs:`, with an optional scope such as `feat(signal):`.
4. Every test is `tests/<name>.salam` plus a `tests/<name>.out` golden holding
   its exact stdout, and `main` ends with `ret testing.Summary()`. Tests never
   read the terminal and may not sleep longer than the runner's watchdog.

## License

GPL-3.0-or-later, the same license family as Salam itself. See
[LICENSE](LICENSE).
