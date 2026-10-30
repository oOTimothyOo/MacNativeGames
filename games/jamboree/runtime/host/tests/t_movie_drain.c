// Synthetic codec queue: exercise the real native-texture output and pump.
// No game files, VideoToolbox session, GPU or audio device are used.
#include "../hle.h"
#undef HLE_FORCE
#undef HLE
#define HLE_FORCE(m, why, ret, name, ...) static ret name(__VA_ARGS__)
#define HLE(m, ret, name, ...) static ret name(__VA_ARGS__)
#include "../hle_movie.c"
#include <time.h>

uint64_t now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }
void *guest_sym(const char *name) { (void)name; return NULL; }
void dm_host_helper_qos(qos_class_t q) { (void)q; }
void gate_obs_set(int id, void (*fn)(const uint64_t *)) { (void)id; (void)fn; }
void *dm_guest_thread_spawn(void (*fn)(void *), void *arg, int prio, size_t stack_size) {
    (void)fn; (void)arg; (void)prio; (void)stack_size; abort();
}

// These codecs are not reached by the drain-only AVC fixture.
vpx_codec_iface_t *vpx_codec_vp9_dx(void) { abort(); }
vpx_codec_err_t vpx_codec_dec_init_ver(vpx_codec_ctx_t *c, vpx_codec_iface_t *i, const vpx_codec_dec_cfg_t *cfg, vpx_codec_flags_t f, int v) {
    (void)c; (void)i; (void)cfg; (void)f; (void)v; abort();
}
vpx_codec_err_t vpx_codec_decode(vpx_codec_ctx_t *c, const uint8_t *d, unsigned int n, void *u, long dl) {
    (void)c; (void)d; (void)n; (void)u; (void)dl; abort();
}
vpx_image_t *vpx_codec_get_frame(vpx_codec_ctx_t *c, vpx_codec_iter_t *i) { (void)c; (void)i; abort(); }
vpx_codec_err_t vpx_codec_destroy(vpx_codec_ctx_t *c) { (void)c; abort(); }
const char *vpx_codec_error(const vpx_codec_ctx_t *c) { (void)c; abort(); }

struct mavc { int queued, taken; };
mavc *mavc_new(void) { return calloc(1, sizeof(mavc)); }
void mavc_free(mavc *a) { free(a); }
int mavc_queued(const mavc *a) { return a->queued; }
int mavc_take(mavc *a, int flush, uint8_t *dst, int w, int h, int64_t *pts) {
    if (!a->queued || !flush) return 0;
    a->queued--; a->taken++;
    memset(dst, a->taken, (size_t)w * h * 4);
    *pts = a->taken * 16667;
    return 1;
}
int mavc_decode(mavc *a, const uint8_t *p, int n, int64_t pts) { (void)a; (void)p; (void)n; (void)pts; abort(); }
void mavc_param_sets(mavc *a, const uint8_t *p, size_t n) { (void)a; (void)p; (void)n; }
void mavc_avcc(mavc *a, const uint8_t *p, size_t n) { (void)a; (void)p; (void)n; }
void mavc_set_rgba(mavc *a) { (void)a; }
void mavc_drop(mavc *a) { a->queued = 0; }

static uint64_t fake_texture, fake_event;
static int output_events, texture_writes, checks, failures;
static void *buffer_data(const void *buffer) { (void)buffer; return &fake_texture; }
static size_t buffer_capacity(const void *buffer) { (void)buffer; return sizeof fake_texture; }
static void signal_event(void *event) { if (event == &fake_event) output_events++; }
int nvn_host_write_texture(const void *tex, const void *src, int w, int h, size_t row, int *tw, int *th) {
    (void)tex; (void)w; (void)h; (void)row;
    if (tw) *tw = 4; if (th) *th = 4;
    if (src) texture_writes++;
    return 0x25;
}
int nvn_host_signal_sync(void *sync) { (void)sync; return 0; }
#undef CHECK
#define CHECK(label, value) do { checks++; if (!(value)) { failures++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

static void run_case(int delayed_frames, int native_texture) {
    mdec_t d = {0}; void *self[2] = {0, &d};
    pthread_mutex_init(&d.mu, NULL); pthread_mutex_init(&d.dmu, NULL);
    pthread_mutex_init(&d.wmu, NULL); pthread_cond_init(&d.wcv, NULL);
    d.type = MD_TYPE_AVC; d.fmt = MD_FMT_ABGR;
    d.mode = native_texture ? MD_MODE_TEX : 1;
    d.nout = MD_NOUT_VIDEO; d.w = d.h = 4; d.started = d.in_eos = 1;
    d.avc = mavc_new(); d.avc->queued = delayed_frames; d.avc_drain = delayed_frames != 0;
    for (int i = 0; i < d.nout; i++) d.out[i].used = 1; // Client holds every output slot.
    d.ev[1] = &fake_event; G.data = buffer_data; G.cap = buffer_capacity; G.signal = signal_event;
    atomic_store(&g_video_eos, 0); output_events = texture_writes = 0;
    pthread_create(&d.wk, NULL, md_worker, &d);
    int64_t previous_pts = -1;
    int index = 0, left = 0; uint32_t flags = 0;
    for (int i = 0; i <= delayed_frames; i++) {
        CHECK("EOS is not reported before its output is consumed", atomic_load(&g_video_eos) == 0);
        if (native_texture) CHECK("native texture output returned", h_movie_GetOut(self, index, &fake_texture) == 0);
        else CHECK("explicit output release returned", h_movie_RelOut(self, index) == 0);
        if (i == delayed_frames) break;
        int64_t pts = 0;
        int result = h_movie_AcqOut(self, &index, &pts, &flags, &left);
        CHECK("freeing one slot resumes the AVC drain", result == 0);
        if (result) break;
        CHECK("delayed frames retain presentation order", pts > previous_pts); previous_pts = pts;
        CHECK("EOS appears only on the final delayed frame", !!(flags & 4) == (i == delayed_frames - 1));
    }
    CHECK("all delayed pictures drained", mavc_queued(d.avc) == 0);
    CHECK("drain state cleared", d.avc_drain == 0);
    CHECK("each delayed output signalled to the client", output_events == delayed_frames);
    if (native_texture) {
        CHECK("native EOS is delivered after the last picture", !!atomic_load(&g_video_eos) == (delayed_frames != 0));
        CHECK("each delayed picture reaches the texture", texture_writes == delayed_frames);
    }
    CHECK("no phantom output after the drain", h_movie_AcqOut(self, &index, &previous_pts, &flags, &left) == MD_NO_OUTPUT);
    md_job(&d, MDJ_QUIT); pthread_join(d.wk, NULL);
    for (int i = 0; i < d.nout; i++) free(d.out[i].frm);
    pthread_cond_destroy(&d.wcv); pthread_mutex_destroy(&d.wmu);
    pthread_mutex_destroy(&d.dmu); pthread_mutex_destroy(&d.mu);
}
int main(void) {
    run_case(4, 1); run_case(1, 1); run_case(0, 1); run_case(4, 0);
    printf("movie drain: %d checks, %d failed\n", checks, failures);
    return failures != 0;
}
