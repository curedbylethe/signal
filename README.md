# signal

`signal` provides POSIX signal sets, per-thread signal masks, and `SIGWINCH`
install-and-wait support for the Salam programming language.

> Early development. POSIX support is tested on Linux and macOS. Windows
> compiles against a stub and has no `SIGWINCH` support.

## Features

- Wait for `SIGWINCH` without polling.
- Use bounded waits with explicit result statuses.
- Create signal sets and control the calling thread's signal mask.
- Install and restore signal handlers with shared ownership.
- Compile Windows consumers against safe stub functions.

## Install

Install Salam 0.6.1 or later using the [Salam installation instructions](https://github.com/SalamLang/Salam).

If your project does not have a Salam manifest, create one:

```sh
salam init
```

Add `signal` to your project:

```sh
salam add github.com/curedbylethe/signal@v0.2.0
```

Commit `salam.toml` and `salam.lock` with your project.

## Quick start

This program waits for `SIGWINCH` and prints when the terminal sends a resize
signal. `WaitWinch` parks until a resize signal arrives.

```salam
import mem
import "github.com/curedbylethe/signal"

func main:
    if not signal.WinchSupported():
        ret
    end

    prev := signal.InstallWinchHandler()
    if prev == null:
        ret
    end
    defer mem.Free(prev)
    defer signal.Restore(signal.WinchSignal, prev)

    set := signal.NewWinchSet()
    if set == null:
        ret
    end
    defer mem.Free(set)

    if signal.WaitWinch(set) == signal.WinchSignal:
        println "terminal resized"
    end
end
```

## Usage

### SIGWINCH and waits

`Wait` waits without a time limit. `WaitTimeout` waits for a bounded time and
requires a prior `Install`; on Darwin, each timed wait accepts exactly one
signal, while Linux accepts any set. Block signals on the calling thread before
waiting; `InstallWinchHandler` blocks `SIGWINCH` for you. After installation,
only one process-wide wait can run at a time; a concurrent wait returns
`WaitBusy`.

The wait statuses are `WaitArrived` (`1`), `WaitTimedOut` (`0`), `WaitInvalid`
(`-1`), `WaitFailed` (`-2`), and `WaitBusy` (`-3`). `WaitWinch` is a specialized
wait for `SIGWINCH` that returns the signal number or a negative status.

### Signal sets

Create a set, add signal numbers, check membership, and change the calling
thread's mask:

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
        _ := signal.Unblock(set)
    end
end
```

### Windows

Windows has no `SIGWINCH`. `WinchSupported()` is false, `Install` returns
`null`, `Wait` and `WaitTimeout` return `WaitInvalid`, and `WaitWinch` returns
`0`. For resize detection, poll `term.Size()` every 20 ms.

## Common problems

- Windows has no `SIGWINCH`; poll `term.Size()` every 20 ms for resize changes.
- Block a signal on the calling thread before waiting. `InstallWinchHandler`
  blocks `SIGWINCH` during installation.
- After `Install`, another concurrent waiter receives `WaitBusy`.
- Before any install, `WaitTimeout` returns `WaitInvalid`.
- A custom handler must call only async-signal-safe functions, save `errno` on
  entry, and restore it before returning.
- Darwin's `WaitTimeout` accepts exactly one signal in its set per call.
- `WaitTimedOut` is `0`, not success; `WaitWinch` returns `0` only on Windows.
- `WaitTimeout` needs a prior `Install` to create its wait state.
- Standard signals can coalesce, so repeated raises may produce one pending
  signal rather than one notification per event.

## Documentation

- [API reference](docs/reference.md)
- [Design and platform contracts](docs/design.md)
- [Contributing](CONTRIBUTING.md)

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
