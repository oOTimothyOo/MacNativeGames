// Eden-compatible unsupported-reduction fallback, exercised through the real factory.
#include "../nvn/nvn_mtl.m"
void *front_metal_layer(void){return NULL;}
module_t *module_of(const void*p){(void)p;return NULL;}
module_t g_mod[MAX_MOD];int g_nmod;
void svc_thread_dump(void){}
uint64_t now_ns(void){return bp_now();}
static int checks,failed;
#define CHECK(c,label) do{checks++;if(!(c)){failed++;fprintf(stderr,"FAIL: %s\n",label);}}while(0)
int main(void){@autoreleasepool{
    mtl_init();BOOL nativeReduction=[g_dev supportsFamily:MTLGPUFamilyApple10];
    NSError*error=nil;id<MTLLibrary>lib=[g_dev newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal;\n"
       "kernel void sample_it(texture2d<float>t[[texture(0)]],sampler s[[sampler(0)]],device float4*out[[buffer(0)]]){out[0]=t.sample(s,float2(.5),level(0));out[1]=t.sample(s,float2(1.25,.25),level(0));}\n"
       options:nil error:&error];
    CHECK(lib!=nil,"test library compiles");if(!lib)return 2;
    id<MTLComputePipelineState>ps=[g_dev newComputePipelineStateWithFunction:[lib newFunctionWithName:@"sample_it"] error:&error];
    CHECK(ps!=nil,"test pipeline compiles");if(!ps)return 2;
    MTLTextureDescriptor*td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA32Float width:2 height:2 mipmapped:NO];td.storageMode=MTLStorageModeShared;td.usage=MTLTextureUsageShaderRead;
    id<MTLTexture>texture=[g_dev newTextureWithDescriptor:td];
    float data[]={0,0,0,1, 1,0,0,1, 0,1,0,1, 1,1,0,1};
    [texture replaceRegion:MTLRegionMake2D(0,0,2,2) mipmapLevel:0 withBytes:data bytesPerRow:32];
    id<MTLCommandQueue>queue=[g_dev newCommandQueue];
    for(int reduction=0;reduction<3;reduction++){
      samp_par p={.minf=1,.magf=1,.ws=1,.wt=1,.wr=1,.reduction=reduction,.lod_min=0,.lod_max=4,.aniso=1};
      mtl_reg_samp(reduction+1,&p);
      id<MTLSamplerState>sampler=samp_by_id(reduction+1);
      CHECK(sampler!=nil,"requested sampler created on this device");if(!sampler)continue;
      CHECK(g_srid[reduction+1]!=0,"created sampler has a GPU resource ID");
      CHECK(sampler==samp_by_id(reduction+1),"sampler factory cache reused");
      id<MTLBuffer>out=[g_dev newBufferWithLength:32 options:MTLResourceStorageModeShared];memset(out.contents,0xcc,32);
      id<MTLCommandBuffer>cb=[queue commandBuffer];id<MTLComputeCommandEncoder>en=[cb computeCommandEncoder];
      [en setComputePipelineState:ps];[en setTexture:texture atIndex:0];[en setSamplerState:sampler atIndex:0];[en setBuffer:out offset:0 atIndex:0];
      [en dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];[en endEncoding];[cb commit];[cb waitUntilCompleted];
      CHECK(cb.status==MTLCommandBufferStatusCompleted&&!cb.error,"sampling completed without GPU error");
      float *v=out.contents;float want=!reduction||!nativeReduction?.5f:reduction==1?0:1;
      CHECK(fabsf(v[0]-want)<1e-6f&&fabsf(v[1]-want)<1e-6f,"requested filtering retained rather than dummy nearest");
      CHECK(v[2]==0&&v[3]==1,"other channels retained");
      CHECK(fabsf(v[4])<1e-6f&&fabsf(v[5])<1e-6f,"requested repeat addressing retained");
    }
    printf("%d checks, %d failures; native reduction supported=%d\n",checks,failed,nativeReduction);return failed?1:0;
}}
