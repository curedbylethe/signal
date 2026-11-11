# API reference

This package provides POSIX signal sets, per-thread signal masks, and
`SIGWINCH` install-and-wait support. Consumers import
`github.com/curedbylethe/signal`. Repository tests and the local build include
the same source with `include "../signal.salam"` because the test harness does
not resolve package imports.

The `///` comments beside public declarations in
[`signal.salam`](../signal.salam) define exact signatures and edge behavior.
This page summarizes the public surface.

## Constants

| Name | Value | Meaning |
|---|---:|---|
| `WinchSignal` | 28 | The `SIGWINCH` number on macOS and Linux, where the watch is enabled. |
| `WaitArrived` | 1 | A signal arrived, and the output block contains its number. |
| `WaitTimedOut` | 0 | A bounded wait expired; only `WaitTimeout` returns this value. |
| `WaitInvalid` | -1 | The input is invalid or the target lacks the requested support. |
| `WaitFailed` | -2 | The kernel wait failed, and the output block remains untouched. |
| `WaitBusy` | -3 | Another thread in this process owns the wait. |
| `SignalSetSize` | platform-specific | The size in bytes of a native signal set. |

`SignalSetSize` is 4 bytes on macOS and OpenBSD, 16 bytes on FreeBSD and
NetBSD, 128 bytes on Linux, and 0 on Windows.

## SIGWINCH and waits

| Function | Signature | Purpose |
|---|---|---|
| `WinchSupported` | `WinchSupported(): bool` | Reports whether this target supports `SIGWINCH`. It returns false on Windows. |
| `NewWinchSet` | `NewWinchSet(): void*` | Allocates a set containing only `SIGWINCH`. The caller owns and frees the set. |
| `InstallWinchHandler` | `InstallWinchHandler(): void*` | Installs the package's no-op handler and blocks `SIGWINCH` on the calling thread. It returns a caller-owned snapshot or null. |
| `Install` | `Install(sig: int, handler: void*): void*` | Installs a handler, blocks the signal on the calling thread, and returns a caller-owned snapshot. A null handler means `SIG_DFL`. |
| `Restore` | `Restore(sig: int, prev: void*): bool` | Drops an install reference. The last reference restores the disposition and pre-block mask captured by the first install. |
| `BlockWinch` | `BlockWinch(): bool` | Blocks `SIGWINCH` on the calling thread. |
| `Wait` | `Wait(set: void*, out: void*): int` | Waits without a time bound. On arrival, it writes the signal number as an i32 to `out`. |
| `WaitTimeout` | `WaitTimeout(set: void*, out: void*, millis: int): int` | Waits for up to `millis` milliseconds. It writes the signal number only on arrival. Zero probes once; negative values are invalid. |
| `WaitWinch` | `WaitWinch(set: void*): int` | Waits for `SIGWINCH` and returns its number or a negative status. It returns 0 on Windows. |
| `WakeWinch` | `WakeWinch(): bool` | Queues `SIGWINCH` for this process, waking a waiting thread. |

Block the signal on the calling thread before waiting so it queues instead of
running on an arbitrary thread. `InstallWinchHandler` blocks it as part of
installation. `Wait` and `WaitTimeout` share one process-wide waiter claim. A
concurrent waiter receives `WaitBusy`.

`WaitTimeout` requires a prior install. On Darwin, each call accepts a set
containing exactly one signal; Linux accepts any set. Other POSIX targets
return `WaitInvalid` because the package has no bounded-wait implementation
there. Only a timed wait can return `WaitTimedOut`.

## Signal sets and masks

| Function | Signature | Purpose |
|---|---|---|
| `NewSet` | `NewSet(): void*` | Allocates an empty set. The caller owns and frees it. |
| `FillSet` | `FillSet(set: void*)` | Adds every signal supported by the platform. It does nothing for null or on Windows. |
| `AddSignal` | `AddSignal(set: void*, sig: int): bool` | Adds one positive signal number to the set. |
| `DelSignal` | `DelSignal(set: void*, sig: int): bool` | Removes one positive signal number from the set. |
| `IsSignal` | `IsSignal(set: void*, sig: int): bool` | Checks whether the set contains a positive signal number. |
| `Block` | `Block(set: void*): bool` | Blocks every signal in the set on the calling thread. |
| `Unblock` | `Unblock(set: void*): bool` | Unblocks every signal in the set on the calling thread. |
| `SetMask` | `SetMask(set: void*): bool` | Replaces the calling thread's signal mask with the set. |
| `CurrentMask` | `CurrentMask(): void*` | Returns an allocated copy of the calling thread's mask. The caller owns and frees it. |

Boolean set operations return false for invalid inputs or failed operations.
On Windows, set allocation and mask reads return null, membership and
mutation operations return false, and `FillSet` does nothing. Free allocated
sets and install snapshots with `mem.Free`.

## Windows

Windows has no `SIGWINCH` or native signal sets. This package keeps the same
call surface through safe stubs. `WinchSupported` returns false; `NewSet`,
`NewWinchSet`, `CurrentMask`, `Install`, and `InstallWinchHandler` return null;
`Wait` and `WaitTimeout` return `WaitInvalid`; and `WaitWinch` returns 0.
`Restore`, `BlockWinch`, `WakeWinch`, `Block`, `Unblock`, `SetMask`,
`AddSignal`, and `DelSignal` return false. `IsSignal` returns false, and
`FillSet` does nothing. For resize detection, poll `term.Size()` every 20 ms.

See [design and platform contracts](design.md) for details about ownership,
handler safety, and implementation constraints.
