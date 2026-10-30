// Actual NVN replay: the GPU writes indirect records after the CPU has submitted
// them. The driver's CPU-filled base-instance word cannot describe those draws.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void) { return NULL; }
module_t *module_of(const void *p) { (void)p; return NULL; }
module_t g_mod[MAX_MOD]; int g_nmod;
void svc_thread_dump(void) {}
uint64_t now_ns(void) { return bp_now(); }
static int checks, failed;
#define CHECK(c, label) do { checks++; if (!(c)) { failed++; fprintf(stderr, "FAIL: %s\n", label); } } while (0)

static unsigned run_case(NSString *source, int variant, int mode) {
    NSError *error = nil;
    MTLCompileOptions *options = [MTLCompileOptions new]; options.preserveInvariance = YES;
    id<MTLLibrary> lib = [g_dev newLibraryWithSource:source options:options error:&error];
    CHECK(lib != nil, "vertex library compiled"); if (!lib) return UINT_MAX;
    NvShader *vs = [NvShader new]; vs->stage = 0; vs->fn = [lib newFunctionWithName:@"main0"];
    vs->ae = [vs->fn newArgumentEncoderWithBufferIndex:0]; vs->arg_len = vs->ae.encodedLength;
    vs->rf.nb = 2; vs->rf.drv_read[0] = 1;
    vs->rf.b[0] = (nvn_rbind){.kind = NVN_RB_DRV0, .aid = 0};
    vs->rf.b[1] = (nvn_rbind){.kind = NVN_RB_SBUFP, .reg = 0, .aid = 1, .rw = 1};
    NvProg *program = [NvProg new]; program->sh[0] = vs;
    prog_t cp = {.serial = 28000 + variant * 10 + mode}; serial_put(cp.serial, program);
    uint8_t *memory; size_t bytes = 4 * (size_t)getpagesize();
    if (posix_memalign((void **)&memory, getpagesize(), bytes)) abort();
    memset(memory, 0xcc, bytes); mtl_pool_add(memory, bytes);
    uint32_t *out = (uint32_t *)memory;
    uint32_t *record = (uint32_t *)(memory + 4096), *indices = (uint32_t *)(memory + 8192);
    indices[0] = 0; indices[1] = 2; indices[2] = 1; indices[3] = 3;
    unsigned base = mode == 0 ? 7 : mode == 1 ? 5 : 9;
    state_reset(); memset(&R, 0, sizeof R);
    tex_t target = {.magic = MAGIC('T','E','X',0), .serial = 28200 + variant * 10 + mode};
    target.d.width = target.d.height = 8;
    target.d.depth = target.d.samples = target.d.levels = 1;
    target.d.target = NVN_TEXTURE_TARGET_2D; target.d.format = NVN_FORMAT_RGBA8;
    R.has_rt = 1; R.rt.n = 1; R.rt.color[0] = &target;
    S.prog = &cp; S.ssbo[0][0] = (p_bind_buf){.stage = 0, .addr = (uint64_t)memory, .size = 128};
    mtl_sub_begin();
    if (mode) {
        // Neither the draw nor encode_args reads this GPU-written record on CPU.
        NSString *kernel = @"#include <metal_stdlib>\nusing namespace metal;\n"
            "kernel void make_args(device uint*dst[[buffer(0)]],constant uint2&p[[buffer(1)]]) {"
            "dst[0]=3;dst[1]=2;if(p.x==1){dst[2]=4;dst[3]=p.y;}"
            "else{dst[2]=1;dst[3]=2;dst[4]=p.y;}}";
        id<MTLLibrary> kl = [g_dev newLibraryWithSource:kernel options:nil error:&error];
        id<MTLComputePipelineState> ps = kl ? [g_dev newComputePipelineStateWithFunction:[kl newFunctionWithName:@"make_args"] error:&error] : nil;
        CHECK(ps != nil, "indirect-record producer compiled");
        if (!ps) abort();
        MTL4ArgumentTableDescriptor *td = [MTL4ArgumentTableDescriptor new]; td.maxBufferBindCount = 2;
        id<MTL4ArgumentTable> table = [g_dev newArgumentTableWithDescriptor:td error:&error];
        id<MTLBuffer> args; size_t off = arena_alloc(8, &args);
        uint32_t params[2] = {(uint32_t)mode, base}; memcpy((uint8_t *)args.contents + off, params, 8);
        void *buffer; uint64_t offset, gpu;
        CHECK(mtl_gpu_addr((uint64_t)record, 20, &buffer, &offset, &gpu), "indirect record mapped");
        [table setAddress:gpu atIndex:0]; [table setAddress:args.gpuAddress + off atIndex:1];
        id<MTL4ComputeCommandEncoder> en = enc_c_begin(NULL);
        [en setArgumentTable:table]; enc_c_pso(en, ps);
        enc_c_dispatch(en, MTLSizeMake(1,1,1), MTLSizeMake(1,1,1)); enc_c_end(en);
    }
    if (mode == 2) {
        p_draw_idx draw_args = {.prim = 0, .itype = 2, .instances = 1,
            .ibuf = (uint64_t)indices, .ind = (uint64_t)record};
        draw(NULL, &draw_args);
    } else {
        p_draw draw_args = {.prim = 0, .first = 4, .count = mode ? 0 : 3,
            .instances = mode ? 1 : 2, .base_instance = mode ? 0 : (int)base,
            .ind = mode ? (uint64_t)record : 0};
        draw(&draw_args, NULL);
    }
    CHECK(mtl_wait(mtl_sub_commit(), 5000000000ull), "GPU submission completed");
    CHECK(!mtl_last_commit_error(), "no GPU command error");
    unsigned mismatches = 0;
    for (unsigned instance = 0; instance < 2; instance++) for (unsigned vertex = 0; vertex < 16; vertex++) {
        int selected = mode == 2 ? vertex >= 3 && vertex <= 5 : vertex >= 4 && vertex <= 6;
        uint32_t want = selected ? base + instance : 0xccccccccu;
        mismatches += out[instance * 16 + vertex] != want;
    }
    CHECK(out[32] == 0xccccccccu, "output allocation sentinel preserved");
    if (mode) CHECK(record[mode == 1 ? 3 : 4] == base, "the GPU produced the requested base instance");
    printf("base-instance variant=%s mode=%s mismatches=%u\n", variant ? "corrected" : "baseline",
           mode == 0 ? "direct" : mode == 1 ? "GPU-written arrays indirect" : "GPU-written indexed indirect", mismatches);
    mtl_pool_del(memory); mtl_drain(); free(memory);
    return mismatches;
}

int main(int argc, char **argv) { @autoreleasepool {
    if (argc != 3) return 2;
    mtl_init();
    for (int variant = 0; variant < 2; variant++) {
        NSString *source = [NSString stringWithContentsOfFile:@(argv[variant + 1]) encoding:NSUTF8StringEncoding error:nil];
        CHECK(source != nil, "synthetic fixture readable"); if (!source) return 2;
        for (int mode = 0; mode < 3; mode++) {
            unsigned mismatches = run_case(source, variant, mode);
            CHECK(variant || !mode ? mismatches == 0 : mismatches == 6,
                  "baseline reproduces wrong transforms only for indirect draws; correction handles every draw");
        }
    }
    printf("t_base_instance: %d checks, %d failures\n", checks, failed);
    return failed ? 1 : 0;
} }
