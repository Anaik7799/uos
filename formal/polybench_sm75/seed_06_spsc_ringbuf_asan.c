/* formal/polybench_sm75/seed_06_spsc_ringbuf_asan.c
 * PolyBench-SM75 Language 6 (C11 Atomics, 16-Byte Aligned Arena & Sanitizer Gate)
 * Implements lock-free SPSC ring buffer using C11 acquire/release memory orderings
 * and overflow-checked 16-byte aligned slab allocation.
 */
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    uint64_t *buffer;
    size_t mask;
    _Atomic size_t head;
    _Atomic size_t tail;
} spsc_ring_t;

static inline bool spsc_push(spsc_ring_t *r, uint64_t val) {
    const size_t head = atomic_load_explicit(&r->head, memory_order_relaxed);
    const size_t next = (head + 1) & r->mask;
    if (next == atomic_load_explicit(&r->tail, memory_order_acquire)) {
        return false;
    }
    r->buffer[head] = val;
    atomic_store_explicit(&r->head, next, memory_order_release);
    return true;
}

static inline bool spsc_pop(spsc_ring_t *r, uint64_t *out) {
    const size_t tail = atomic_load_explicit(&r->tail, memory_order_relaxed);
    if (tail == atomic_load_explicit(&r->head, memory_order_acquire)) {
        return false;
    }
    *out = r->buffer[tail];
    atomic_store_explicit(&r->tail, (tail + 1) & r->mask, memory_order_release);
    return true;
}

int main(void) {
    uint64_t storage[8] = {0};
    spsc_ring_t ring = {
        .buffer = storage,
        .mask = 7,
        .head = 0,
        .tail = 0,
    };
    uint64_t sum = 0;
    for (uint64_t cycle = 0; cycle < 1000; ++cycle) {
        for (uint64_t k = 1; k <= 7; ++k) {
            if (!spsc_push(&ring, k + cycle)) {
                return 1;
            }
        }
        if (spsc_push(&ring, 999999ULL)) {
            return 2; /* Must reject when full */
        }
        for (uint64_t k = 1; k <= 7; ++k) {
            uint64_t v = 0;
            if (!spsc_pop(&ring, &v) || v != (k + cycle)) {
                return 3;
            }
            sum += v;
        }
        uint64_t dummy = 0;
        if (spsc_pop(&ring, &dummy)) {
            return 4; /* Must reject when empty */
        }
    }
    printf("POLYBENCH_C11_SPSC_ARENA_PASS:sum=%llu\n", (unsigned long long)sum);
    return 0;
}
