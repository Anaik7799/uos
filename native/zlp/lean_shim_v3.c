#define _GNU_SOURCE
#include <lean/lean.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <pthread.h>
#include <sys/prctl.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

extern void lean_initialize_runtime_module(void);
extern lean_object* initialize_UosZlpHyperplane(uint8_t builtin);
extern void lean_initialize_thread(void);
extern void lean_finalize_thread(void);

extern uint64_t uos_zlp_verify_frame(lean_object* payload);
extern uint8_t  uos_zlp_zenoh_topic_guard(lean_object* topic);
extern uint64_t uos_zlp_heavy_graph_digest(lean_object* payload, uint32_t rounds);

/* ── Heavy-Lane Async Worker Pool (epoll + eventfd + lean_initialize_thread) ── */
typedef struct {
    uint64_t req_id;
    uint32_t rounds;
    lean_object* owned_sarray;
} heavy_job_t;

typedef struct {
    uint64_t req_id;
    uint64_t digest;
} heavy_done_t;

#define HEAVY_Q_CAP 128
static pthread_mutex_t g_q_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_q_cv = PTHREAD_COND_INITIALIZER;
static heavy_job_t     g_job_q[HEAVY_Q_CAP];
static size_t          g_job_head = 0, g_job_tail = 0, g_job_count = 0;

static pthread_mutex_t g_done_mu = PTHREAD_MUTEX_INITIALIZER;
static heavy_done_t    g_done_q[HEAVY_Q_CAP];
static size_t          g_done_head = 0, g_done_tail = 0, g_done_count = 0;

static int             g_heavy_efd = -1;
static int             g_shutdown = 0;
static pthread_t       g_heavy_tid;

static char            g_zenoh_host[64] = "127.0.0.1";
static uint16_t        g_zenoh_port = 8080;

static void* heavy_worker_main(void* arg) {
    (void)arg;
    lean_initialize_thread();
    while (1) {
        pthread_mutex_lock(&g_q_mu);
        while (g_job_count == 0 && !g_shutdown) {
            pthread_cond_wait(&g_q_cv, &g_q_mu);
        }
        if (g_shutdown && g_job_count == 0) {
            pthread_mutex_unlock(&g_q_mu);
            break;
        }
        heavy_job_t job = g_job_q[g_job_head];
        g_job_head = (g_job_head + 1) % HEAVY_Q_CAP;
        g_job_count--;
        pthread_mutex_unlock(&g_q_mu);

        /* Execute Lean 4 multi-round kernel (consumes owned_sarray reference) */
        uint64_t digest = uos_zlp_heavy_graph_digest(job.owned_sarray, job.rounds);

        pthread_mutex_lock(&g_done_mu);
        if (g_done_count < HEAVY_Q_CAP) {
            g_done_q[g_done_tail] = (heavy_done_t){ .req_id = job.req_id, .digest = digest };
            g_done_tail = (g_done_tail + 1) % HEAVY_Q_CAP;
            g_done_count++;
        }
        pthread_mutex_unlock(&g_done_mu);

        uint64_t one = 1;
        ssize_t wr = write(g_heavy_efd, &one, sizeof(one));
        (void)wr;
    }
    lean_finalize_thread();
    return NULL;
}

int zlp_v3_boot(int* out_epfd, int* out_heavy_efd) {
    /* Anti-Zombie Lock 1: auto-terminate if parent beam.smp dies */
    (void)prctl(PR_SET_PDEATHSIG, SIGTERM);
    signal(SIGPIPE, SIG_IGN);

    const char* env_host = getenv("UOS_ZENOH_REST_HOST");
    if (env_host && env_host[0] != '\0' && strlen(env_host) < sizeof(g_zenoh_host)) {
        strcpy(g_zenoh_host, env_host);
    }
    const char* env_port = getenv("UOS_ZENOH_REST_PORT");
    if (env_port && env_port[0] != '\0') {
        int p = atoi(env_port);
        if (p > 0 && p <= 65535) g_zenoh_port = (uint16_t)p;
    }

    lean_initialize_runtime_module();
    lean_object* res = initialize_UosZlpHyperplane(1);
    if (lean_io_result_is_error(res)) return -1;
    lean_dec_ref(res);
    lean_io_mark_end_initialization();

    int epfd = epoll_create1(EPOLL_CLOEXEC);
    if (epfd < 0) return -2;

    g_heavy_efd = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
    if (g_heavy_efd < 0) { close(epfd); return -3; }

    struct epoll_event ev0 = { .events = EPOLLIN | EPOLLRDHUP, .data.fd = 0 };
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, 0, &ev0) != 0) return -4;

    struct epoll_event eve = { .events = EPOLLIN, .data.fd = g_heavy_efd };
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, g_heavy_efd, &eve) != 0) return -5;

    if (pthread_create(&g_heavy_tid, NULL, heavy_worker_main, NULL) != 0) return -6;

    *out_epfd = epfd;
    *out_heavy_efd = g_heavy_efd;
    return 0;
}

void zlp_v3_shutdown(void) {
    pthread_mutex_lock(&g_q_mu);
    g_shutdown = 1;
    pthread_cond_broadcast(&g_q_cv);
    pthread_mutex_unlock(&g_q_mu);
    (void)pthread_join(g_heavy_tid, NULL);
}

int zlp_epoll_wait_one(int epfd, int* out_fd, uint32_t* out_events, int timeout_ms) {
    struct epoll_event ev;
    while (1) {
        int n = epoll_wait(epfd, &ev, 1, timeout_ms);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return n;
        *out_fd = ev.data.fd;
        *out_events = ev.events;
        return 1;
    }
}

int zlp_enqueue_heavy(uint64_t req_id, uint32_t rounds, const uint8_t* bytes, size_t len) {
    lean_object* clone = lean_alloc_sarray(1, len, len);
    if (len > 0) memcpy(lean_sarray_cptr(clone), bytes, len);

    pthread_mutex_lock(&g_q_mu);
    if (g_job_count >= HEAVY_Q_CAP) {
        pthread_mutex_unlock(&g_q_mu);
        lean_dec_ref(clone);
        return -1;
    }
    g_job_q[g_job_tail] = (heavy_job_t){ .req_id = req_id, .rounds = rounds, .owned_sarray = clone };
    g_job_tail = (g_job_tail + 1) % HEAVY_Q_CAP;
    g_job_count++;
    pthread_cond_signal(&g_q_cv);
    pthread_mutex_unlock(&g_q_mu);
    return 0;
}

int zlp_pop_heavy_done(uint64_t* out_req_id, uint64_t* out_digest) {
    uint64_t val = 0;
    while (read(g_heavy_efd, &val, sizeof(val)) > 0) {}

    pthread_mutex_lock(&g_done_mu);
    if (g_done_count == 0) {
        pthread_mutex_unlock(&g_done_mu);
        return 0;
    }
    heavy_done_t d = g_done_q[g_done_head];
    g_done_head = (g_done_head + 1) % HEAVY_Q_CAP;
    g_done_count--;
    pthread_mutex_unlock(&g_done_mu);

    *out_req_id = d.req_id;
    *out_digest = d.digest;
    return 1;
}

/* ── Perceus ST Fast-Lane Slab Wrappers ── */
void* zlp_alloc_slab(size_t cap) { return (void*)lean_alloc_sarray(1, 0, cap); }
uint8_t* zlp_slab_ptr(void* slab) { return lean_sarray_cptr((lean_object*)slab); }
void zlp_set_size(void* slab, size_t len) { lean_to_sarray((lean_object*)slab)->m_size = len; }
uint8_t zlp_is_exclusive(void* slab) { return lean_is_exclusive((lean_object*)slab) ? 1 : 0; }

uint64_t zlp_eval_retain_slab(void* slab) {
    lean_inc_ref((lean_object*)slab);
    return uos_zlp_verify_frame((lean_object*)slab);
}

uint8_t zlp_guard_topic_retain_slab(void* topic_slab, const uint8_t* topic, size_t len) {
    if (len == 0 || len > 512) return 0;
    memcpy(lean_sarray_cptr((lean_object*)topic_slab), topic, len);
    lean_to_sarray((lean_object*)topic_slab)->m_size = len;
    lean_inc_ref((lean_object*)topic_slab);
    return uos_zlp_zenoh_topic_guard((lean_object*)topic_slab);
}

uint32_t zlp_get_pid(void) { return (uint32_t)getpid(); }

/* ── Live c3i-zenoh-router-1 (127.0.0.1:8080) Bounded SSE, PUT & GET Helpers ── */
static int connect_zenoh_router(void) {
    int fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    int one = 1;
    (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(g_zenoh_port);
    if (inet_pton(AF_INET, g_zenoh_host, &addr.sin_addr) != 1) {
        addr.sin_addr.s_addr = htonl(0x7F000001U);
    }
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

int zlp_zenoh_open_sse(int epfd, const uint8_t* topic, size_t topic_len) {
    int fd = connect_zenoh_router();
    if (fd < 0) return -1;
    char req[1024];
    int n = snprintf(req, sizeof(req),
        "GET /%.*s HTTP/1.1\r\n"
        "Host: %s:%u\r\n"
        "Accept: text/event-stream\r\n"
        "\r\n",
        (int)topic_len, (const char*)topic, g_zenoh_host, (unsigned)g_zenoh_port);
    if (n <= 0 || (size_t)n >= sizeof(req)) { close(fd); return -2; }
    ssize_t wr = send(fd, req, (size_t)n, MSG_NOSIGNAL);
    if (wr != n) { close(fd); return -3; }

    int fl = fcntl(fd, F_GETFL, 0);
    (void)fcntl(fd, F_SETFL, fl | O_NONBLOCK);

    struct epoll_event ev = { .events = EPOLLIN | EPOLLRDHUP, .data.fd = fd };
    if (epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &ev) != 0) {
        close(fd);
        return -4;
    }
    return fd;
}

int zlp_zenoh_put(const uint8_t* topic, size_t topic_len, const uint8_t* body, size_t body_len) {
    int fd = connect_zenoh_router();
    if (fd < 0) return -1;
    char hdr[1024];
    int hn = snprintf(hdr, sizeof(hdr),
        "PUT /%.*s HTTP/1.1\r\n"
        "Host: %s:%u\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n\r\n",
        (int)topic_len, (const char*)topic, g_zenoh_host, (unsigned)g_zenoh_port, body_len);
    if (hn <= 0 || (size_t)hn >= sizeof(hdr)) { close(fd); return -2; }
    if (send(fd, hdr, (size_t)hn, MSG_NOSIGNAL) != hn) { close(fd); return -3; }
    size_t off = 0;
    while (off < body_len) {
        ssize_t w = send(fd, body + off, body_len - off, MSG_NOSIGNAL);
        if (w <= 0) { close(fd); return -4; }
        off += (size_t)w;
    }
    char resp[256];
    ssize_t r = recv(fd, resp, sizeof(resp) - 1, 0);
    close(fd);
    if (r <= 12) return -5;
    resp[r] = '\0';
    return (strstr(resp, "200 OK") != NULL) ? 0 : -6;
}

int zlp_zenoh_get(const uint8_t* topic, size_t topic_len, uint8_t* out_buf, size_t max_out) {
    int fd = connect_zenoh_router();
    if (fd < 0) return -1;
    char req[1024];
    int n = snprintf(req, sizeof(req),
        "GET /%.*s HTTP/1.1\r\n"
        "Host: %s:%u\r\n"
        "Accept: application/json\r\n"
        "Connection: close\r\n\r\n",
        (int)topic_len, (const char*)topic, g_zenoh_host, (unsigned)g_zenoh_port);
    if (n <= 0 || (size_t)n >= sizeof(req)) { close(fd); return -2; }
    if (send(fd, req, (size_t)n, MSG_NOSIGNAL) != n) { close(fd); return -3; }

    size_t total = 0;
    while (total + 1 < max_out) {
        ssize_t r = recv(fd, out_buf + total, max_out - 1 - total, 0);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        total += (size_t)r;
    }
    close(fd);
    if (total <= 12) return -4;
    out_buf[total] = '\0';
    if (strstr((const char*)out_buf, "200 OK") == NULL) return -5;
    const char* body = strstr((const char*)out_buf, "\r\n\r\n");
    if (!body) return -6;
    body += 4;
    size_t body_len = total - (size_t)(body - (const char*)out_buf);
    if (body_len > 0) memmove(out_buf, body, body_len);
    return (int)body_len;
}
