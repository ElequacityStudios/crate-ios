#include "CodeRegion.h"

#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
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

crate_region_status crate_code_region_claim(size_t size, bool ask_debugger, crate_code_region *out) {
    size_t page = (size_t)getpagesize();
    size = (size + page - 1) / page * page;

    void *exec = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (exec == MAP_FAILED) return CRATE_REGION_MAP_FAILED;

    if (ask_debugger && ask_debugger_to_authorize(exec, size) != (uint64_t)exec) {
        munmap(exec, size);
        return CRATE_REGION_REFUSED;
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

    out->executable = exec;
    out->writable = (void *)write;
    out->size = size;
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
