#include "CodeRegion.h"

#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <unistd.h>

/* Not in the public SDK, but a stable libSystem wrapper of the csops syscall. */
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

#define CS_OPS_STATUS 0

bool crate_jit_cs_flags(uint32_t *flags) {
    return csops(getpid(), CS_OPS_STATUS, flags, sizeof *flags) == 0;
}

bool crate_jit_traced(void) {
    struct kinfo_proc info;
    size_t size = sizeof info;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) return false;
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

/* Stops for the debugger, which prepares the pages and resumes past the
   instruction. Returns x0 as the debugger left it: the address again, unless
   it put an error code there. */
static uint64_t ask_debugger_to_authorize(void *start, size_t size) {
#if defined(__arm64__)
    register uint64_t x0 __asm__("x0") = (uint64_t)start;
    register uint64_t x1 __asm__("x1") = (uint64_t)size;
    __asm__ volatile("brk #0x69" : "+r"(x0) : "r"(x1) : "memory");
    return x0;
#else
    (void)size;
    return (uint64_t)start;
#endif
}

/* StikJIT's and StikDebug's scripts send each page's address to debugserver in
   9 hex digits, so they authorize only pages below 64 GiB: above, they write
   to the wrong address, and running from the region kills the process. */
#define AUTHORIZABLE_END (64ULL << 30)

uint64_t crate_code_region_first_offer;

static void *map_executable(size_t size, bool below_64_gib) {
    void *first = NULL;
#if DEBUG
    /* Test hook: start where the crashes that found the 64 GiB limit had it. */
    if (getenv("CRATE_TEST_HIGH_REGION")) first = (void *)0x7000000000ULL;
#endif
    void *exec = mmap(first, size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    crate_code_region_first_offer = exec == MAP_FAILED ? 0 : (uint64_t)exec;
    if (exec == MAP_FAILED || !below_64_gib || (uint64_t)exec + size <= AUTHORIZABLE_END) return exec;
    munmap(exec, size);
    /* Where iOS put it was too high (with extended virtual addressing it often
       is): hint lower, 1 GiB at a time from 4 GiB, until a hint is taken. */
    for (uint64_t hint = 4ULL << 30; hint + size <= AUTHORIZABLE_END; hint += 1ULL << 30) {
        exec = mmap((void *)hint, size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (exec == MAP_FAILED) continue;
        if ((uint64_t)exec + size <= AUTHORIZABLE_END) return exec;
        munmap(exec, size);
    }
    errno = ENOMEM;
    return MAP_FAILED;
}

crate_region_status crate_code_region_map(size_t size, bool below_64_gib, crate_code_region *out) {
    size_t page = (size_t)getpagesize();
    size = (size + page - 1) / page * page;
    void *exec = map_executable(size, below_64_gib);
    if (exec == MAP_FAILED) return CRATE_REGION_MAP_FAILED;
    out->executable = exec;
    out->writable = NULL;
    out->size = size;
    return CRATE_REGION_OK;
}

crate_region_status crate_code_region_finish(crate_code_region *region, bool ask_debugger) {
    void *exec = region->executable;
    size_t size = region->size;

    if (ask_debugger) {
        if ((uint64_t)exec + size > AUTHORIZABLE_END) {
            munmap(exec, size);
            return CRATE_REGION_REFUSED;
        }
        if (ask_debugger_to_authorize(exec, size) != (uint64_t)exec) {
            munmap(exec, size);
            return CRATE_REGION_REFUSED;
        }
    }

    /* vm_remap rather than mach_vm_remap, whose header the iOS SDK refuses; on
       arm64 they take the same 64-bit addresses. FALSE: share the pages. */
    vm_address_t write = 0;
    vm_prot_t cur, max;
    kern_return_t kr = vm_remap(mach_task_self(), &write, size, 0, VM_FLAGS_ANYWHERE,
                                mach_task_self(), (vm_address_t)exec, FALSE,
                                &cur, &max, VM_INHERIT_NONE);
    if (kr != KERN_SUCCESS) {
        munmap(exec, size);
        return CRATE_REGION_REMAP_FAILED;
    }
    if (mprotect((void *)write, size, PROT_READ | PROT_WRITE) != 0) {
        int saved = errno;
        munmap((void *)write, size);
        munmap(exec, size);
        errno = saved;
        return CRATE_REGION_PROTECT_FAILED;
    }
    region->writable = (void *)write;
    return CRATE_REGION_OK;
}

bool crate_code_region_test(const crate_code_region *region) {
#if defined(__arm64__)
    /* mov w0, #42; ret */
    static const uint32_t code[] = {0x52800540, 0xd65f03c0};
    memcpy(region->writable, code, sizeof code);
    sys_icache_invalidate(region->executable, sizeof code);
    int (*answer)(void) = (int (*)(void))region->executable;
    bool ok = answer() == 42;
    memset(region->writable, 0, sizeof code);
    sys_icache_invalidate(region->executable, sizeof code);
    return ok;
#else
    (void)region;
    return false;
#endif
}
