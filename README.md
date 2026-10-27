# signal

POSIX signal primitives for the [Salam](https://github.com/SalamLang/Salam)
programming language: general POSIX signal sets plus the `SIGWINCH` listening
plumbing extracted from
[basalam](https://github.com/curedbylethe/basalam)'s resize watcher.

The package owns the process-wide handler and the blocked signal mask, and
nothing else: no terminal state, no policy, no widget code.

> **Status: 0.1.0, early development.** The `SIGWINCH` API is a
> behaviour-identical move of `basalam/signal.salam`; the signal-set API is new.
> Hardening is tracked separately.

## Install

You need the Salam compiler, version 0.5.9 or later:

```sh
{ curl -fsSL https://raw.githubusercontent.com/SalamLang/Salam/refs/heads/main/install.sh || wget -qO- https://raw.githubusercontent.com/SalamLang/Salam/refs/heads/main/install.sh; } | sh
```

Add signal with Salam's package manager:

```sh
salam add github.com/curedbylethe/signal@v0.1.0
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

    // The handler comes first: a signal blocked while its disposition is
    // still SIG_DFL is discarded at generation on Darwin.
    signal.InstallWinchHandler()
    signal.BlockWinch()

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
        signal.Block(set)
        // A sigwait on the set now covers both signals.
        signal.Unblock(set)
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
| `InstallWinchHandler` | Install the process-wide no-op handler |
| `BlockWinch` | Add `SIGWINCH` to the calling thread's mask |
| `WaitWinch` | Park until `SIGWINCH` is queued, return its number, or 0 |
| `WakeWinch` | Send `SIGWINCH` to this process to break the wait |

### Signal sets

| Name | Purpose |
|---|---|
| `SignalSetSize` | Bytes in a platform signal set: 4 on macOS and OpenBSD, 16 on FreeBSD, NetBSD and DragonFly, 128 on Linux, 0 on Windows |
| `NewSet` | Allocate an empty caller-owned set |
| `FillSet` | Add every signal to a set |
| `AddSignal` | Add one signal number; false when the number is invalid or unsupported |
| `DelSignal` | Remove one signal number; false when the number is invalid or unsupported |
| `IsSignal` | True when the set contains the number |
| `Block` | Block every signal in the set on the calling thread |
| `Unblock` | Unblock every signal in the set on the calling thread |
| `SetMask` | Replace the calling thread's mask with the set |

CI builds and tests macOS and Linux only, so the BSD values and the Windows
stubs are not exercised by CI. The signal-set API is on `main` and not in the
`v0.1.0` tag; it ships in the next release.

## Contributing

`make check` runs the format check, the build, and the test suite locally.
`make test-llvm` runs the same tests with the LLVM backend. CI runs both on
ubuntu and macos.

## License

GPL-3.0-or-later, the same license family as Salam itself. See
[LICENSE](LICENSE).
