// Content-free regression: pipeline lookahead must not change a draw's scissor.
// Full and partial uniform updates also exercise argument and upload rollover.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

static void run_case(int mode) {
    enum { W = 128, H = 64 };
    int draws = mode ? 4200 : 64;
    NSError *error = nil;
    NSString *text = @"#include <metal_stdlib>\nusing namespace metal;\n"
        "struct U{float4 _m0[4096];};struct A{constant U*vp_c3[[id(0)]];};"
        "struct O{float4 p[[position]];float4 c[[user(locn0)]];};\n"
        "vertex O v(uint id[[vertex_id]],constant A&a[[buffer(0)]]){"
        "float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};"
        "return{float4(p[id],0,1),(*a.vp_c3)._m0[0]+(*a.vp_c3)._m0[1]};}\n"
        "fragment float4 f(O i[[stage_in]]){return i.c;}\n";
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:text options:nil error:&error];
    CHECK(lib != nil, "library compiled");
    if (!lib) return;
    NvProg *pr = [NvProg new]; NvShader *vs = [NvShader new], *fs = [NvShader new];
    pr->sh[0] = vs; pr->sh[1] = fs;
    vs->stage = 0; vs->fn = [lib newFunctionWithName:@"v"];
    vs->rf.nb = 1; vs->rf.b[0] = (nvn_rbind){.kind = NVN_RB_CBUF, .reg = 0, .aid = 0};
    vs->ae = [vs->fn newArgumentEncoderWithBufferIndex:0];
    vs->arg_len = vs->ae.encodedLength; vs->cb_ext[0] = 32;
    fs->stage = 1; fs->fn = [lib newFunctionWithName:@"f"];
    fs->rf.color_known = 1; fs->rf.color_mask = 1;
    prog_t cp = {0}; cp.serial = 29000 + mode; serial_put(cp.serial, pr);
    uint8_t *mem, *commands;
    size_t page = getpagesize();
    if (posix_memalign((void **)&mem, page, 131072) ||
        posix_memalign((void **)&commands, page, 1048576)) abort();
    memset(mem, 0, 131072); memset(commands, 0, 1048576);
    mtl_pool_add(mem, 131072); mtl_pool_add(commands, 1048576);
    // A short, actually read range near the pool's end, with a 64 KiB declaration.
    float *uniform = (float *)(mem + 131072 - 256);
    uniform[3] = 1; uniform[4] = 1;
    tex_t target = {.magic = MAGIC('T','E','X',0), .serial = 29100 + mode};
    target.d.width = W; target.d.height = H;
    target.d.depth = target.d.samples = target.d.levels = 1;
    target.d.target = NVN_TEXTURE_TARGET_2D; target.d.format = NVN_FORMAT_RGBA8;
    size_t used = 0;
#define EMIT(OP, X) do { size_t z = (8 + sizeof(X) + 7) & ~7ull; \
    op_hdr h = {OP, (uint32_t)z}; memcpy(commands + used, &h, 8); \
    memcpy(commands + used + 8, &(X), sizeof(X)); used += z; } while (0)
    p_set_rt rt = {.n = 1}; rt.color[0] = &target; EMIT(OP_SET_RT, rt);
    p_viewports vp = {.n = 1}; vp.v[0][2] = W; vp.v[0][3] = H; EMIT(OP_VIEWPORTS, vp);
    p_clear_color clear = {.index = 0, .mask = 15, .rgba = {0,0,0,1}};
    EMIT(OP_CLEAR_COLOR, clear);
    p_bind_program bp = {&cp, 3}; EMIT(OP_BIND_PROGRAM, bp);
    p_bind_buf binding = {.stage = 0, .index = 0, .addr = (uint64_t)uniform, .size = 32};
    EMIT(OP_BIND_UBO, binding);
    for (int i = 0; i < draws; i++) {
        if (mode) {
            float value[] = {0,0,0,1, (i & 1) ? 0 : 1, (i & 1) ? 1 : 0, 0,0};
            uint64_t dst = (uint64_t)uniform + (mode == 2 ? 16 : 0);
            uint64_t n = mode == 2 ? 16 : 32;
            op_hdr header = {OP_UPDATE_UB, (uint32_t)(24 + n)};
            memcpy(commands + used, &header, 8);
            memcpy(commands + used + 8, &dst, 8);
            memcpy(commands + used + 16, &n, 8);
            memcpy(commands + used + 24, value + (mode == 2 ? 4 : 0), n);
            used += 24 + n;
        }
        p_scissor sc = {i % W, i / W, 1, 1}; EMIT(OP_SCISSOR, sc);
        p_draw d = {.prim = 4, .first = 0, .count = 3, .instances = 1}; EMIT(OP_DRAW, d);
    }
    op_hdr end = {OP_END, 8}; memcpy(commands + used, &end, 8);
#undef EMIT
    CHECK(used + 8 < 1048576, "command allocation bounds");
    state_reset(); memset(&R, 0, sizeof R); mtl_sub_begin();
    id<MTLBuffer> unused;
    arena_alloc((4u << 20) - 256, &unused);
    uint64_t handle = (uint64_t)commands;
    mtl_sub_index(&handle, 1); mtl_exec(commands);
    id<MTLBuffer> out = [g_dev newBufferWithLength:W * H * 4 options:MTLResourceStorageModeShared];
    res_add(out);
    [blit() copyFromTexture:tex_mtl(&target) sourceSlice:0 sourceLevel:0
        sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(W,H,1)
        toBuffer:out destinationOffset:0 destinationBytesPerRow:W * 4 destinationBytesPerImage:W * H * 4];
    CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull), "GPU submission completed");
    CHECK(!mtl_last_commit_error(), "no GPU command error");
    unsigned mismatches[2] = {0,0}; const uint8_t *pixels = out.contents;
    for (int flip = 0; flip < 2; flip++) for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
        int i = (flip ? H - 1 - y : y) * W + x;
        uint8_t want[4] = {0,0,0,255};
        if (i < draws) { want[0] = !mode || !(i & 1) ? 255 : 0; want[1] = mode && (i & 1) ? 255 : 0; }
        if (memcmp(pixels + (y * W + x) * 4, want, 4)) mismatches[flip]++;
    }
    // Include the first draw. Before the fix it is clipped to the final draw's
    // pixel by pso_predict_rest, even with no uniform updates (mode 0).
    CHECK(!mismatches[0] || !mismatches[1], "every draw kept its scissor and uniform bytes");
    printf("scissor/uniform mode %d: pixel mismatches %u/%u; updater ring offset %zu\n",
           mode, mismatches[0], mismatches[1], g_ubs_off);
    mtl_pool_del(commands); mtl_pool_del(mem); mtl_drain(); free(commands); free(mem);
}

int main(void) {
    @autoreleasepool {
        mtl_init();
        for (int mode = 0; mode < 3; mode++) run_case(mode);
        printf("t_pso_scissor: %d checks, %d failures\n", checks, failed);
        return failed ? 1 : 0;
    }
}
