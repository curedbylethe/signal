/* -std=c11 turns on __STRICT_ANSI__, which hides sigaction and SA_RESTART in
   glibc's <signal.h>; ask for POSIX 2008 before any include. */
#define _POSIX_C_SOURCE 200809L

/*
 * The oracle for signal.salam's hand-built `struct sigaction`.
 *
 * signal.salam does not declare the C struct; it writes a zeroed heap block at
 * named offsets. This file is what makes those offsets checkable: it asserts
 * them against the platform's own <signal.h> and then performs a real
 * sigaction() round trip, so a table that compiles but lies about the layout
 * fails here instead of corrupting sa_flags in the field.
 *
 * Run by `make check-abi` on Darwin and Linux, and by the abi-* CI jobs in
 * FreeBSD, NetBSD and OpenBSD VMs. Keep the numbers in step with the
 * _SIGACTION_SIZE / _SA_FLAGS_WORD / _SA_RESTART block in signal.salam.
 */
#include <signal.h>
#include <stddef.h>
#include <stdio.h>

#if defined(__APPLE__)
#  define PLATFORM         "darwin"
#  define HANDLER_FIELD    __sigaction_u
#  define EXPECT_SIZE      16
#  define EXPECT_MASK      8
#  define EXPECT_MASK_SIZE 4
#  define EXPECT_FLAGS     12
#  define EXPECT_RESTART   0x0002
#elif defined(__OpenBSD__)
#  define PLATFORM         "openbsd"
#  define HANDLER_FIELD    __sigaction_u
#  define EXPECT_SIZE      16
#  define EXPECT_MASK      8
#  define EXPECT_MASK_SIZE 4
#  define EXPECT_FLAGS     12
#  define EXPECT_RESTART   0x0002
#elif defined(__NetBSD__)
#  define PLATFORM         "netbsd"
#  define HANDLER_FIELD    _sa_u
#  define EXPECT_SIZE      32
#  define EXPECT_MASK      8
#  define EXPECT_MASK_SIZE 16
#  define EXPECT_FLAGS     24
#  define EXPECT_RESTART   0x0002
#elif defined(__FreeBSD__)
#  define PLATFORM         "freebsd"
#  define HANDLER_FIELD    __sigaction_u
#  define EXPECT_SIZE      32
#  define EXPECT_MASK      12
#  define EXPECT_MASK_SIZE 16
#  define EXPECT_FLAGS     8
#  define EXPECT_RESTART   0x0002
#elif defined(__linux__)
#  define PLATFORM         "linux"
#  define HANDLER_FIELD    __sigaction_handler
#  define EXPECT_SIZE      152
#  define EXPECT_MASK      8
#  define EXPECT_MASK_SIZE 128
#  define EXPECT_FLAGS     136
#  define EXPECT_RESTART   0x10000000
#else
#  error "no sigaction table for this platform"
#endif

_Static_assert(sizeof(struct sigaction) == EXPECT_SIZE, "sizeof(struct sigaction)");
_Static_assert(offsetof(struct sigaction, HANDLER_FIELD) == 0, "handler offset");
_Static_assert(offsetof(struct sigaction, sa_mask) == EXPECT_MASK, "sa_mask offset");
_Static_assert(offsetof(struct sigaction, sa_flags) == EXPECT_FLAGS, "sa_flags offset");
_Static_assert(sizeof(((struct sigaction *)0)->sa_mask) == EXPECT_MASK_SIZE,
               "sa_mask size must match SignalSetSize");

/* FreeBSD is the only target whose sa_flags precedes sa_mask; the numbers above
   do not say so out loud, and a reader diffing the tables needs it to. */

/* SA_RESTART is not exposed by every BSD under every feature macro; assert it
   where it is visible and rely on EXPECT_RESTART's literal otherwise. */
#ifdef SA_RESTART
_Static_assert(SA_RESTART == EXPECT_RESTART, "SA_RESTART value");
#endif

static void handler(int sig) { (void)sig; }

int main(void) {
    struct sigaction act = {0}, old = {0}, cur = {0}, back = {0};

    act.sa_handler = handler;
    act.sa_flags = EXPECT_RESTART;
    if (sigaction(SIGUSR1, &act, &old) != 0) { perror("install"); return 1; }
    if (old.sa_handler != SIG_DFL) { fprintf(stderr, "previous disposition was not SIG_DFL\n"); return 2; }

    if (sigaction(SIGUSR1, NULL, &cur) != 0) { perror("read"); return 3; }
    if (cur.sa_handler != handler) { fprintf(stderr, "handler did not round trip\n"); return 4; }
    if ((cur.sa_flags & EXPECT_RESTART) == 0) { fprintf(stderr, "SA_RESTART did not round trip\n"); return 5; }

    if (sigaction(SIGUSR1, &old, NULL) != 0) { perror("restore"); return 6; }
    if (sigaction(SIGUSR1, NULL, &back) != 0) { perror("read back"); return 7; }
    if (back.sa_handler != SIG_DFL) { fprintf(stderr, "restore did not put SIG_DFL back\n"); return 8; }

    printf("ok %s: size=%zu mask=%zu flags=%zu restart=0x%x\n",
           PLATFORM, sizeof(struct sigaction),
           offsetof(struct sigaction, sa_mask),
           offsetof(struct sigaction, sa_flags), (unsigned)EXPECT_RESTART);
    return 0;
}
