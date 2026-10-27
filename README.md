# signal

POSIX signal primitives for the [Salam](https://github.com/SalamLang/Salam)
programming language: the `SIGWINCH` listening plumbing extracted from
[basalam](https://github.com/curedbylethe/basalam)'s resize watcher.

The package owns the process-wide handler and the blocked signal mask, and
nothing else: no terminal state, no policy, no widget code.

> **Status: 0.1.0, early development.** This is a behaviour-identical move of
> `basalam/signal.salam`; hardening is tracked separately.

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

```salam
import "github.com/curedbylethe/signal"

import mem

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

| Name | Purpose |
|---|---|
| `WinchSignal` | The `SIGWINCH` number, 28 on macOS and Linux |
| `WinchSupported` | True on POSIX, false on the Windows stub surface |
| `NewWinchSet` | Allocate a caller-owned signal set holding only `SIGWINCH` |
| `InstallWinchHandler` | Install the process-wide no-op handler |
| `BlockWinch` | Add `SIGWINCH` to the calling thread's mask |
| `WaitWinch` | Park until `SIGWINCH` is queued, return its number, or 0 |
| `WakeWinch` | Send `SIGWINCH` to this process to break the wait |

## Contributing

`make check` runs the format check, the build, and the test suite locally.
`make test-llvm` runs the same tests with the LLVM backend. CI runs both on
ubuntu and macos.

## License

GPL-3.0-or-later, the same license family as Salam itself. See
[LICENSE](LICENSE).
