#ifndef CRATE_CODE_REGION_H
#define CRATE_CODE_REGION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* The executable memory crate's translator writes code into, claimed once per
   launch. See JIT.swift for when it is claimed and why only once. */

/* This process's code-signing flags (CS_DEBUGGED, CS_GET_TASK_ALLOW, ...).
   False if iOS wouldn't say. */
bool crate_jit_cs_flags(uint32_t *flags);

/* Whether a debugger is tracing this process right now (P_TRACED): the one that
   would answer `brk #0x69`. */
bool crate_jit_traced(void);

typedef struct {
    /* Where code runs. */
    void *executable;
    /* The same pages, mapped again to be written. */
    void *writable;
    size_t size;
} crate_code_region;

typedef enum {
    CRATE_REGION_OK = 0,
    /* mmap of the executable mapping failed: errno says why. */
    CRATE_REGION_MAP_FAILED,
    /* The debugger answered the trap with an error in x0 instead of resuming
       with the address. */
    CRATE_REGION_REFUSED,
    /* mach_vm_remap of the writable alias failed. */
    CRATE_REGION_REMAP_FAILED,
    /* mprotect of the alias failed: errno says why. */
    CRATE_REGION_PROTECT_FAILED,
} crate_region_status;

/* Maps `size` bytes (rounded up to whole pages) executable, then, when
   `ask_debugger` is set, stops on `brk #0x69` with the address in x0 and the
   length in x1 for the attached debugger to authorize them (iOS 26 and later),
   and last maps a writable alias of the same pages. In that order: made the
   other way round the authorized pages fault when run.

   Only call with `ask_debugger` while crate_jit_traced() is true. With no
   debugger to answer it the trap kills the process. */
crate_region_status crate_code_region_claim(size_t size, bool ask_debugger, crate_code_region *out);

/* Writes a function that returns 42 into the region, runs it, and says whether
   it returned 42. If the pages weren't really authorized, iOS kills the process
   here instead. */
bool crate_code_region_test(const crate_code_region *region);

#endif
