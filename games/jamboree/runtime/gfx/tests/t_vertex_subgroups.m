// Content-free GPU semantic checks for real vertex subgroups and divergent lanes.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <sys/stat.h>
static int checks,failed;
#define CHECK(label,condition) do {checks++;if(!(condition)){failed++;fprintf(stderr,"%s failed\n",label);}}while(0)
int main(int argc,char**argv){@autoreleasepool{
    umask(0077);if(argc!=2)return 2;
    id<MTLDevice>d=MTLCreateSystemDefaultDevice();
    NSString *helpers=[NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:nil];
    NSString *source=[@"#include <metal_stdlib>\nusing namespace metal;\n" stringByAppendingString:helpers];
    source=[source stringByAppendingString:@"\n"
      "struct Args{uint first,count,mode,stride;};\n"
      "vertex void probe(uint v[[vertex_id]],uint inst[[instance_id]],constant Args&a[[buffer(0)]],device uint4*records[[buffer(1)]],device atomic_uint*counter[[buffer(2)]],device uint*ids[[buffer(3)]]) {\n"
      " uint entryLane=dm_native_lane_id();uint entrySelf=simd_shuffle(v,entryLane);\n"
      " if(a.mode && v%3==1)return;\n"
      " uint lane=dm_native_lane_id();ulong mask=(simd_vote::vote_t)simd_ballot(true);\n"
      " uint first=uint(ctz(mask)),n=popcount(mask);uint base=0;\n"
      " if(lane==first){base=atomic_fetch_add_explicit(counter+inst*2,n,memory_order_relaxed);atomic_fetch_add_explicit(counter+inst*2+1,1u,memory_order_relaxed);}\n"
      " base=simd_shuffle(base,first);uint4 lt=dm_native_lt_mask();\n"
      " uint rank=popcount(mask & (ulong(lt.x)|(ulong(lt.y)<<32)));\n"
      " records[inst*a.stride+v]=uint4(lane,simd_shuffle(v,lane)==v,entrySelf==v,rank);\n"
      " ids[inst*a.stride+base+rank]=v;\n"
      "}\n"];
    NSError *error=nil;MTLCompileOptions *options=[MTLCompileOptions new];options.preserveInvariance=YES;
    id<MTLLibrary>lib=[d newLibraryWithSource:source options:options error:&error];
    if(!lib){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 3;}
    MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"probe"];pd.rasterizationEnabled=NO;
    id<MTLRenderPipelineState>ps=[d newRenderPipelineStateWithDescriptor:pd error:&error];
    if(!ps){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 4;}
    id<MTLCommandQueue>q=[d newCommandQueue];
    for(uint32_t first=0;first<=17;first+=17)for(uint32_t count=1;count<=129;count=count==1?31:count==31?32:count==32?33:count==33?97:count==97?129:130)for(uint32_t mode=0;mode<2;mode++){
      uint32_t args[]={first,count,mode,256};
      id<MTLBuffer>ab=[d newBufferWithBytes:args length:sizeof args options:MTLResourceStorageModeShared];
      id<MTLBuffer>records=[d newBufferWithLength:256*2*16 options:MTLResourceStorageModeShared];
      id<MTLBuffer>counter=[d newBufferWithLength:16 options:MTLResourceStorageModeShared];
      id<MTLBuffer>ids=[d newBufferWithLength:256*2*4 options:MTLResourceStorageModeShared];
      memset(records.contents,0xcc,records.length);memset(ids.contents,0xcc,ids.length);memset(counter.contents,0,counter.length);
      id<MTLCommandBuffer>cb=[q commandBuffer];MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor new];rp.renderTargetWidth=rp.renderTargetHeight=rp.defaultRasterSampleCount=1;
      id<MTLRenderCommandEncoder>en=[cb renderCommandEncoderWithDescriptor:rp];[en setRenderPipelineState:ps];
      [en setVertexBuffer:ab offset:0 atIndex:0];[en setVertexBuffer:records offset:0 atIndex:1];[en setVertexBuffer:counter offset:0 atIndex:2];[en setVertexBuffer:ids offset:0 atIndex:3];
      [en drawPrimitives:MTLPrimitiveTypePoint vertexStart:first vertexCount:count instanceCount:2];[en endEncoding];[cb commit];[cb waitUntilCompleted];
      CHECK("GPU completed",cb.status==MTLCommandBufferStatusCompleted && cb.error==nil);
      uint32_t *c=counter.contents,*out=ids.contents,*r=records.contents;
      for(uint32_t inst=0;inst<2;inst++){
        uint32_t selected=0;for(uint32_t v=first;v<first+count;v++)if(!mode||v%3!=1)selected++;
        CHECK("compaction count",c[inst*2]==selected);
        CHECK("real groups do not become singleton groups",!selected||count<31||c[inst*2+1]<selected);
        CHECK("compaction output sentinel",out[inst*256+selected]==0xccccccccu);
        bool seen[256]={0};
        for(uint32_t n=0;n<selected;n++){
          uint32_t v=out[inst*256+n];bool valid=v>=first&&v<first+count&&(!mode||v%3!=1);
          CHECK("compacted vertex in range",valid);if(v<256){CHECK("each selected vertex once",!seen[v]);seen[v]=true;}
        }
        for(uint32_t v=0;v<256;v++){
          bool selectedVertex=v>=first&&v<first+count&&(!mode||v%3!=1);
          if(selectedVertex){CHECK("physical lane self-shuffle",r[(inst*256+v)*4+1]==1);CHECK("entry lane self-shuffle",r[(inst*256+v)*4+2]==1);CHECK("selected output exists",seen[v]);}
          else CHECK("unselected record untouched",r[(inst*256+v)*4]==0xccccccccu);
        }
      }
    }
    printf("%d checks, %d failures\n",checks,failed);
    return failed?1:0;
}}
