/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2013 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "GTMSenTestCase.h"

#import "PLCrashAsyncThread.h"
#import "PLCrashTestThread.h"

#import <pthread.h>

@interface PLCrashAsyncThreadTests : SenTestCase {
@private
    plcrash_test_thread_t _thr_args;
}

@end

@implementation PLCrashAsyncThreadTests


- (void) setUp {
    plcrash_test_thread_spawn(&_thr_args);
}

- (void) tearDown {
    plcrash_test_thread_stop(&_thr_args);
}

- (void) testGetRegName {
    plcrash_async_thread_state_t ts;
    plcrash_async_thread_state_mach_thread_init(&ts, pthread_mach_thread_np(_thr_args.thread));
    
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&ts); i++) {
        const char *name = plcrash_async_thread_state_get_reg_name(&ts, i);
        STAssertNotNULL(name, @"Register name for %d is NULL", i);
        STAssertNotEquals((size_t)0, strlen(name), @"Register name for %d is 0 length", i);
    }
}

- (void) testGetSetRegister {
    plcrash_async_thread_state_t ts;
    plcrash_async_thread_state_mach_thread_init(&ts, pthread_mach_thread_np(_thr_args.thread));
    
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&ts); i++) {
        plcrash_greg_t reg;
        
        plcrash_async_thread_state_set_reg(&ts, i, 5);
        plcrash_async_thread_state_get_reg(&ts, i, &reg);
        STAssertEquals(reg, (plcrash_greg_t)5, @"Unexpected register value");
    }
}

/* Test plcrash_async_thread_state_ucontext_init() */
- (void) testThreadStateContextInit {
    plcrash_async_thread_state_t thr_state;
    ucontext_t uap;
    _STRUCT_MCONTEXT mcontext_data;

    memset(&mcontext_data, 'A', sizeof(mcontext_data));
    uap.uc_mcontext = &mcontext_data;
    
    plcrash_async_thread_state_ucontext_init(&thr_state, &uap);
    
#if defined(PLCRASH_ASYNC_THREAD_ARM_SUPPORT)
    STAssertTrue(memcmp(&thr_state.arm_state.thread, &uap.uc_mcontext->__ss, sizeof(thr_state.arm_state.thread)) == 0, @"Incorrectly copied");
    
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT) && defined(__LP64__)
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts64, &uap.uc_mcontext->__ss, sizeof(thr_state.x86_state.thread.uts.ts64)) == 0, @"Incorrectly copied");
    
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int) x86_EXCEPTION_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int) x86_EXCEPTION_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es64, &uap.uc_mcontext->__es, sizeof(thr_state.x86_state.exception.ues.es64)) == 0, @"Incorrectly copied");
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT)
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE32_COUNT, @"Incorrect thread state count for a 32-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE32, @"Incorrect thread state flavor for a 32-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts32, &uap.uc_mcontext->__ss, sizeof(thr_state.x86_state.thread.uts.ts32)) == 0, @"Incorrectly copied");
    
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int)x86_EXCEPTION_STATE32_COUNT, @"Incorrect thread state count for a 32-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int)x86_EXCEPTION_STATE32, @"Incorrect thread state flavor for a 32-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es32, &uap.uc_mcontext->__es, sizeof(thr_state.x86_state.exception.ues.es32)) == 0, @"Incorrectly copied");
#else
#error Add platform support
#endif
}

/* Test plframe_thread_state_thread_init() */
- (void) testThreadStateThreadInit {
    plcrash_async_thread_state_t thr_state;
    mach_msg_type_number_t state_count;
    thread_t thr;
    
    /* Spawn a test thread */
    thr = pthread_mach_thread_np(_thr_args.thread);
    thread_suspend(thr);

    /* Fetch the thread state */
    STAssertEquals(plcrash_async_thread_state_mach_thread_init(&thr_state, thr), PLCRASH_ESUCCESS, @"Failed to initialize thread state");
    
    /* Test the results */
#if defined(PLCRASH_ASYNC_THREAD_ARM_SUPPORT)
    arm_thread_state_t local_thr_state;
    state_count = ARM_THREAD_STATE_COUNT;
    
    STAssertEquals(thread_get_state(thr, ARM_THREAD_STATE, (thread_state_t) &local_thr_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.arm_state.thread, &local_thr_state, sizeof(thr_state.arm_state.thread)) == 0, @"Incorrectly copied");
    
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT) && defined(__LP64__)
    state_count = x86_THREAD_STATE64_COUNT;
    x86_thread_state64_t local_thr_state;
    STAssertEquals(thread_get_state(thr, x86_THREAD_STATE64, (thread_state_t) &local_thr_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts64, &local_thr_state, sizeof(thr_state.x86_state.thread.uts.ts64)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    
    state_count = x86_EXCEPTION_STATE64_COUNT;
    x86_exception_state64_t local_exc_state;
    STAssertEquals(thread_get_state(thr, x86_EXCEPTION_STATE64, (thread_state_t) &local_exc_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es64, &local_exc_state, sizeof(thr_state.x86_state.exception.ues.es64)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int) x86_EXCEPTION_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int) x86_EXCEPTION_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT)
    state_count = x86_THREAD_STATE32_COUNT;
    x86_thread_state32_t local_thr_state;
    STAssertEquals(thread_get_state(thr, x86_THREAD_STATE32, (thread_state_t) &local_thr_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts32, &local_thr_state, sizeof(thr_state.x86_state.thread.uts.ts32)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE32_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE32, @"Incorrect thread state flavor for a 32-bit system");
    
    state_count = x86_EXCEPTION_STATE32_COUNT;
    x86_exception_state32_t local_exc_state;
    STAssertEquals(thread_get_state(thr, x86_EXCEPTION_STATE32, (thread_state_t) &local_exc_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es32, &local_exc_state, sizeof(thr_state.x86_state.exception.ues.es32)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int) x86_EXCEPTION_STATE32_COUNT, @"Incorrect thread state count for a 32-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int) x86_EXCEPTION_STATE32, @"Incorrect thread state flavor for a 32-bit system");
#else
#error Add platform support
#endif
    
    /* Clean up */
    thread_resume(thr);
}

@end
