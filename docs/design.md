# Design and platform contracts

`signal` provides POSIX signal primitives, including the process-wide setup
needed to wait for terminal resize notifications. It does not own terminal
state, decide when watching starts, or interpret a wake-up. The caller reads
the terminal size again after `SIGWINCH` arrives.

## Signal ownership

The registry owns each installed signal for the process. The first `Install`
captures the signal disposition and the calling thread's mask, installs the
handler, and then blocks the signal on that thread. Later installs of the same
handler increment a reference count and return separate caller-owned copies
of the original snapshot. The package rejects a different handler while the
signal is owned, so callers do not receive a handle for a handler that will
never run.

When more than one reference exists, `Restore` only drops the reference
count. The last restore puts back the disposition and mask captured by the
first install, then frees the registry snapshot. Callers own and free their
copies. The mask belongs to a thread, so restore normally runs on the
installing thread. A new thread inherits its creator's mask and can take over
the wait.

`InstallWinchHandler` installs a no-op handler before blocking `SIGWINCH`.
That order matters on Darwin: generating a blocked signal while `SIG_DFL` is
still installed discards the signal, so a later wait could park forever. The
handler keeps the signal queued. The signal number only means that the
terminal size may have changed.

## Wait behavior

Callers must block the relevant signals before waiting. POSIX delivers a
pending blocked signal to exactly one waiting thread, without specifying which
thread receives it. The registry therefore allows only one `Wait` or
`WaitTimeout` call at a time. Another concurrent call returns `WaitBusy`
rather than splitting deliveries.

Standard signals coalesce. Repeated raises while a signal is blocked can
leave only one pending instance. A wake-up means “check the state again,” not
“one resize occurred.”

`Wait` uses `sigwait` and has no timeout. `WaitTimeout` requires registry
state created by a prior install and allocates nothing on the wait path.
Linux uses `sigtimedwait` for a bounded wait over any set. Darwin uses a kqueue
`EVFILT_SIGNAL` filter to measure the bound, then uses `sigwait` to consume the
pending signal. Darwin registers one filter per signal, so each bounded wait
accepts exactly one signal in its set. If another source consumes a signal
after a generation is counted, the wait reports a timeout when no signal
remains pending.

The five statuses distinguish arrival (`WaitArrived`), timeout
(`WaitTimedOut`), invalid input or unsupported bounded waits (`WaitInvalid`),
kernel failure (`WaitFailed`), and another active waiter (`WaitBusy`). The
output block is written only on arrival. `WaitTimeout` with zero milliseconds
probes once. `WaitWinch` returns the signal number or a negative status; zero
is reserved for its Windows stub.

## Handler safety

A custom handler passed to `Install` runs on the thread that took the signal.
It may call only async-signal-safe functions. It must not allocate, lock, use
stdio, or call the Salam runtime. It may touch only `volatile sig_atomic_t`,
lock-free atomics, or read-only data. It must save `errno` on entry and restore
it before returning. The package's no-op handler meets this contract.

## ABI and platform limits

POSIX targets install dispositions with `sigaction`, never `signal()`. Salam
does not expose a C `struct sigaction` type, so `signal.salam` writes a zeroed
byte block through named, per-platform offsets for Darwin, Linux, FreeBSD,
NetBSD, and OpenBSD. Only `SA_RESTART` is set; `sa_mask` stays empty, and no
restorer is written. FreeBSD places `sa_flags` before `sa_mask`, unlike the
other supported layouts.

[`ci/sigaction_offsets.c`](../ci/sigaction_offsets.c) checks the offsets with
`_Static_assert` against each platform's headers and performs a `sigaction`
round trip. CI runs this oracle on the BSD targets. Salam has no BSD port, so
the BSD branches are checked by the oracle and reviewed, not compiled by this
package.

Darwin and Linux have bounded-wait implementations. Other POSIX targets
support unbounded `Wait`, but `WaitTimeout` returns `WaitInvalid`. Windows
provides safe stubs because it has neither `SIGWINCH` nor `sigset_t`; resize
consumers can poll `term.Size()` every 20 ms. DragonFly is not a Salam target.

This package does not implement a handler body, a self-pipe timeout, or a
`SIGALRM` wake-up. A handler cannot interrupt `sigwait`. An alarm would also
claim process-wide state that the caller may already own. Signal sets use the
platform's libc set operations. On Darwin, the public names are macros, but the
corresponding underscore-prefixed symbols are exported by libSystem and are
called directly.

For declarations and per-function behavior, see the [API reference](reference.md).
