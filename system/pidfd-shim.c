/* This kernel carries an incomplete pidfd backport: pidfd_open succeeds, but the fd is a bare
   anon_inode (/proc/self/fd/N reads "anon_inode:[pidfd]", no pid behind it) and waitid(P_PIDFD)
   returns EINVAL because do_wait cannot resolve it. systemd 259 (safe_fork -> systemd-executor)
   and GLib both take the pidfd path on sight and then fail, so systemd cannot reap or confirm any
   spawned process and every unit ends at Result=resources; GLib's child watch drops every child.

   pidfd_open is called through syscall() by GLib, so it cannot be interposed. A seccomp filter
   installed from this library's constructor answers it with ENOSYS instead, which is what
   upstream kernels without pidfd support do; systemd and GLib then take the waitpid path this
   kernel does implement. Filters are inherited by every child. */
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef SECCOMP_RET_ERRNO
#define SECCOMP_RET_ERRNO 0x00050000U
#endif
#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434
#endif

__attribute__((constructor))
static void rungic_deny_pidfd_open(void)
{
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_AARCH64, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_pidfd_open, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (ENOSYS & SECCOMP_RET_DATA)),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog prog = {
        .len = (unsigned short)(sizeof filter / sizeof filter[0]),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0)
        return;
    (void)syscall(SYS_seccomp, SECCOMP_SET_MODE_FILTER, 0u, &prog);
}
