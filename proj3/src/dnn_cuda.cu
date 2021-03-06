#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#include <cuda_runtime.h>

#define DEBUG
#define THREADS_PER_BLOCK 512
#define INDEX_ROW_MAJOR_2(i, j, I, J) ((j) + (J) * (i))
#define INDEX_ROW_MAJOR_3(i, j, k, I, J, K) ((k) + (K) * ((j) + (J) * (i)))
#define INDEX_ROW_MAJOR_4(i, j, k, l, I, J, K, L) ((l) + (L) * ((k) + (K) * ((j) + (J) * (i))))

#define HANDLE_ERROR(err) (HandleError( err, __FILE__, __LINE__ ))
static void HandleError(cudaError_t err, const char *file, int line)
{
    if (err != cudaSuccess) {
        printf("%s in %s at line %d\n", cudaGetErrorString( err ), file, line);
        exit(EXIT_FAILURE);
    }
}





__global__ void conv_ws(float *I, float *K, float *R, int iw, int ih, int ow, int oh, int kw, int kh, int sw, int sh, int ic, int oc){
    // weight stationary
    int BLOCKS_PER_CHANNEL = ceil(float(ow * oh)/float(THREADS_PER_BLOCK));
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    int pid = bid % BLOCKS_PER_CHANNEL; // pixel block index (within channel)
    int cid = bid / BLOCKS_PER_CHANNEL; // output channel index
    // declare on-chip shared memory
    extern __shared__ float M[];
    // read input data once per block (shared across threads)
    // this process could serve as bottleneck, load distribution is critical
    // distribute indices across threads
    int f = kw*kh*ic;
    int load_per_thread = ceil(float(f)/float(THREADS_PER_BLOCK));
    int l = load_per_thread * tid;
    int u = load_per_thread * (tid + 1);
    if (l < f) {
        for (int idx=l; idx<((u<f)?u:f); idx++){
            int i = idx/ic/kh;
            int j = idx/ic%kh;
            int k = idx%ic;
            M[INDEX_ROW_MAJOR_3(i,j,k, kw,kh,ic)] = K[INDEX_ROW_MAJOR_4(i,j,k,cid, kw,kh,ic,oc)];
        }
    }
    // wait until data is ready
    __syncthreads();
    // compute block index in output pixel dimension
    int ofs = pid * THREADS_PER_BLOCK;
    // handle boundary
    if (tid >= ((ow * oh - ofs < THREADS_PER_BLOCK)? (ow * oh - ofs) : THREADS_PER_BLOCK)) return;
    // retrieve output pixel
    int w = (ofs+tid)/oh;
    int h = (ofs+tid)%oh;
    int w_ofs = w*sw;
    int h_ofs = h*sh;
    float acc = 0;
    // apply convolution
    for (int i=0; i<kw; i++){
        for (int j=0; j<kh; j++){
            for (int k=0; k<ic; k++){
                acc += I[INDEX_ROW_MAJOR_3(w_ofs+i,h_ofs+j,k, iw,ih,ic)] * M[INDEX_ROW_MAJOR_3(i,j,k, kw,kh,ic)];
            }
        }
    }
    R[INDEX_ROW_MAJOR_3(w,h,cid, ow,oh,oc)] = acc;
}
__global__ void conv_is(float *I, float *K, float *R, int iw, int ih, int ow, int oh, int kw, int kh, int sw, int sh, int ic, int oc){
    // input stationary
    int BLOCKS_PER_PIXEL = ceil(float(oc)/float(THREADS_PER_BLOCK));
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    int cid = bid % BLOCKS_PER_PIXEL; // channel block index (within pixel)
    int pid = bid / BLOCKS_PER_PIXEL; // pixel index
    // compute output pixel of the block
    int h = pid % oh;
    int w = pid / oh;
    int w_ofs = w*sw;
    int h_ofs = h*sh;
    // declare on-chip shared memory
    extern __shared__ float M[];
    // read input data once per block (shared across threads)
    // this process could serve as bottleneck, load distribution is critical
    // distribute indices across threads
    int f = kw*kh*ic;
    int load_per_thread = ceil(float(f)/float(THREADS_PER_BLOCK));
    int l = load_per_thread * tid;
    int u = load_per_thread * (tid + 1);
    if (l < f) {
        for (int idx=l; idx<((u<f)?u:f); idx++){
            int i = idx/ic/kh;
            int j = idx/ic%kh;
            int k = idx%ic;
            M[INDEX_ROW_MAJOR_3(i,j,k, kw,kh,ic)] = I[INDEX_ROW_MAJOR_3(w_ofs+i,h_ofs+j,k, iw,ih,ic)];
        }
    }
    // wait until data is ready
    __syncthreads();
    // compute block index in output channel dimension
    int ofs = cid * THREADS_PER_BLOCK;
    // handle boundary
    if (tid >= ((oc - ofs < THREADS_PER_BLOCK)? (oc - ofs) : THREADS_PER_BLOCK)) return;
    // apply convolution
    float acc = 0;
    for (int i=0; i<kw; i++){
        for (int j=0; j<kh; j++){
            for (int k=0; k<ic; k++){
                acc += M[INDEX_ROW_MAJOR_3(i,j,k, kw,kh,ic)] * K[INDEX_ROW_MAJOR_4(i,j,k,ofs+tid, kw,kh,ic,oc)];
            }
        }
    }
    R[INDEX_ROW_MAJOR_3(w,h,ofs+tid, ow,oh,oc)] = acc;
}
extern "C"
void conv2d(float * I, float * K, float * R, int iw, int ih, int ow, int oh, int kw, int kh, int sw, int sh, int ic, int oc) {
    float *dev_I, *dev_K, *dev_R;
    // I: (iw * ih * ic), row major ordered
    // K: (kw * kh * ic * oc), row major ordered
    // R: (ow * oh * oc), row major ordered
    // todo: 2d convolution between I and K
    // loop over outer dimensions, and compute dot product in chunks of size 512
    // kernel function: convolution for a single sliding window
    // allocate the memory on the GPU
    HANDLE_ERROR( cudaMalloc( (void**)&dev_I, iw * ih * ic * sizeof(float) ) );
    HANDLE_ERROR( cudaMalloc( (void**)&dev_K, kw * kh * ic * oc * sizeof(float) ) );
    HANDLE_ERROR( cudaMalloc( (void**)&dev_R, ow * oh * oc * sizeof(float) ) );
    // copy the arrays to the GPU
    HANDLE_ERROR( cudaMemcpy( dev_I, I, iw * ih * ic * sizeof(float), cudaMemcpyHostToDevice ) );
    HANDLE_ERROR( cudaMemcpy( dev_K, K, kw * kh * ic * oc * sizeof(float), cudaMemcpyHostToDevice ) );
    // how to organize blocks?
    // maximizing data reuse and parallelism within a block
    // dynamic on-chip memory allocation
    int BLOCK_MEMSIZE = kw * kh * ic * sizeof(float);
    if (ow*oh > 100 * THREADS_PER_BLOCK){
        // weight stationary
        // within a block, hold kernel and thread over output pixels
        int BLOCKS_PER_CHANNEL = ceil(float(ow*oh)/float(THREADS_PER_BLOCK));
        conv_ws<<<oc*BLOCKS_PER_CHANNEL,THREADS_PER_BLOCK,BLOCK_MEMSIZE>>>(dev_I, dev_K, dev_R, iw, ih, ow, oh, kw, kh, sw, sh, ic, oc);
    }else{
        // input stationary
        // within a block, hold input and thread over output channels
        int BLOCKS_PER_PIXEL = ceil(float(oc)/float(THREADS_PER_BLOCK));
        conv_is<<<ow*oh*BLOCKS_PER_PIXEL,THREADS_PER_BLOCK,BLOCK_MEMSIZE>>>(dev_I, dev_K, dev_R, iw, ih, ow, oh, kw, kh, sw, sh, ic, oc);
    }
    // copy the array back from the GPU to the CPU
    HANDLE_ERROR( cudaMemcpy( R, dev_R, ow * oh * oc * sizeof(float), cudaMemcpyDeviceToHost ) );
    // cleanup
    cudaFree(dev_I); cudaFree(dev_K); cudaFree(dev_R);
}






__global__ void badd(float *I, float *B, float *R, int ow, int oh, int oc){
    int BLOCKS_PER_CHANNEL = ceil(float(ow * oh)/float(THREADS_PER_BLOCK));
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    int pid = bid % BLOCKS_PER_CHANNEL; // pixel block index (within channel)
    int cid = bid / BLOCKS_PER_CHANNEL; // channel index
    // compute block index in output pixel dimension
    int ofs = pid * THREADS_PER_BLOCK;
    // handle boundary
    if (tid >= ((ow * oh - ofs < THREADS_PER_BLOCK)? (ow * oh - ofs) : THREADS_PER_BLOCK)) return;
    // import channelwise parameters to shared memory
    __shared__ float Mem[1];
    if(tid == 0) Mem[0] = B[cid];
    // wait until data is ready
    __syncthreads();
    // add
    ofs = INDEX_ROW_MAJOR_3((ofs + tid)/oh,(ofs + tid)%oh,cid, ow,oh,oc);
    R[ofs] = I[ofs] + Mem[0];
}
extern "C"
void bias_add(float * I, float * B, float * R, int ow, int oh, int oc) {
    float *dev_I, *dev_B, *dev_R;
    // I: (ow * oh * oc), row major ordered
    // B: (oc)
    // R: (ow * oh * oc), row major ordered
    // todo: element-wise addition
    // allocate the memory on the GPU
    cudaMalloc( (void**)&dev_I, ow * oh * oc * sizeof(float) );
    cudaMalloc( (void**)&dev_B, oc * sizeof(float) );
    cudaMalloc( (void**)&dev_R, ow * oh * oc * sizeof(float) );
    // copy the arrays to the GPU
    cudaMemcpy( dev_I, I, ow * oh * oc * sizeof(float), cudaMemcpyHostToDevice );
    cudaMemcpy( dev_B, B, oc * sizeof(float), cudaMemcpyHostToDevice );
    // block = channel, thread over pixels
    int BLOCKS_PER_CHANNEL = ceil(float(ow*oh)/float(THREADS_PER_BLOCK));
    badd<<<oc*BLOCKS_PER_CHANNEL,THREADS_PER_BLOCK>>>(dev_I, dev_B, dev_R, ow, oh, oc);
    // copy the array back from the GPU to the CPU
    cudaMemcpy( R, dev_R, ow * oh * oc * sizeof(float), cudaMemcpyDeviceToHost );
    // cleanup
    cudaFree(dev_I); cudaFree(dev_B); cudaFree(dev_R);
}






__global__ void lr(float *I, float *R, int ow, int oh, int oc){
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    // handle boundary
    int ofs = ow*oh*oc - bid*THREADS_PER_BLOCK;
    if (tid >= (ofs < THREADS_PER_BLOCK? ofs : THREADS_PER_BLOCK)) return;
    // add
    ofs = bid*THREADS_PER_BLOCK+tid;
    float input = I[ofs];
    R[ofs] = (input > 0)? input : input * 0.1f;
}
extern "C"
void leaky_relu(float * I, float * R, int ow, int oh, int oc) {
    float *dev_I, *dev_R;
    // I: (ow * oh * oc), row major ordered
    // R: (ow * oh * oc), row major ordered
    // todo: element-wise rectification
    // allocate the memory on the GPU
    cudaMalloc( (void**)&dev_I, ow * oh * oc * sizeof(float) );
    cudaMalloc( (void**)&dev_R, ow * oh * oc * sizeof(float) );
    // copy the arrays to the GPU
    cudaMemcpy( dev_I, I, ow * oh * oc * sizeof(float), cudaMemcpyHostToDevice );
    // block = channel, thread over pixels
    int BLOCKS = ceil(float(ow*oh*oc)/float(THREADS_PER_BLOCK));
    lr<<<BLOCKS,THREADS_PER_BLOCK>>>(dev_I, dev_R, ow, oh, oc);
    // copy the array back from the GPU to the CPU
    cudaMemcpy( R, dev_R, ow * oh * oc * sizeof(float), cudaMemcpyDeviceToHost );
    // cleanup
    cudaFree(dev_I); cudaFree(dev_R);
}





__global__ void bn(float *I, float *M, float *G, float *V, float *R, float eps, int ow, int oh, int oc){
    int BLOCKS_PER_CHANNEL = ceil(float(ow * oh)/float(THREADS_PER_BLOCK));
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    int pid = bid % BLOCKS_PER_CHANNEL; // pixel block index (within channel)
    int cid = bid / BLOCKS_PER_CHANNEL; // channel index
    // compute block index in output pixel dimension
    int ofs = pid * THREADS_PER_BLOCK;
    // handle boundary
    if (tid >= ((ow * oh - ofs < THREADS_PER_BLOCK)? (ow * oh - ofs) : THREADS_PER_BLOCK)) return;
    // import channelwise parameters to shared memory
    __shared__ float memory[3];
    if(tid == 0){
        memory[0] = G[cid];
        memory[1] = M[cid];
        memory[2] = V[cid];
    }
    // wait until data is ready
    __syncthreads();
    // retrieve output pixel
    ofs = INDEX_ROW_MAJOR_3((ofs + tid)/oh,(ofs + tid)%oh,cid, ow,oh,oc);
    // normalize
    R[ofs] = memory[0] * (I[ofs] - memory[1]) / (sqrt(memory[2]) + eps);
}
extern "C"
void batch_norm(float * I, float * M, float * G, float * V, float * R, float eps, int ow, int oh, int oc){
    float *dev_I, *dev_M, *dev_G, *dev_V, *dev_R;
    // I: (ow * oh * oc), row major ordered
    // M, G, V, R: (oc)
    // R: (ow * oh * oc), row major ordered
    // todo: element-wise normalization
    // allocate the memory on the GPU
    cudaMalloc( (void**)&dev_I, ow * oh * oc * sizeof(float) );
    cudaMalloc( (void**)&dev_M, oc * sizeof(float) );
    cudaMalloc( (void**)&dev_G, oc * sizeof(float) );
    cudaMalloc( (void**)&dev_V, oc * sizeof(float) );
    cudaMalloc( (void**)&dev_R, ow * oh * oc * sizeof(float) );
    // copy the arrays to the GPU
    cudaMemcpy( dev_I, I, ow * oh * oc * sizeof(float), cudaMemcpyHostToDevice );
    cudaMemcpy( dev_M, M, oc * sizeof(float), cudaMemcpyHostToDevice );
    cudaMemcpy( dev_G, G, oc * sizeof(float), cudaMemcpyHostToDevice );
    cudaMemcpy( dev_V, V, oc * sizeof(float), cudaMemcpyHostToDevice );
    // block = channel, thread over pixels
    int BLOCKS_PER_CHANNEL = ceil(float(ow*oh)/float(THREADS_PER_BLOCK));
    bn<<<oc*BLOCKS_PER_CHANNEL,THREADS_PER_BLOCK>>>(dev_I, dev_M, dev_G, dev_V, dev_R, eps, ow, oh, oc);
    // copy the array back from the GPU to the CPU
    cudaMemcpy( R, dev_R, ow * oh * oc * sizeof(float), cudaMemcpyDeviceToHost );
    // cleanup
    cudaFree(dev_I); cudaFree(dev_M); cudaFree(dev_G); cudaFree(dev_V); cudaFree(dev_R);
}





__global__ void mp(float *I, float *R, int iw, int ih, int kw, int kh, int sw, int sh, int ow, int oh, int oc){
    // input stationary
    int BLOCKS_PER_CHANNEL = ceil(float(ow * oh)/float(THREADS_PER_BLOCK));
    int bid = blockIdx.x;
    int tid = threadIdx.x;
    int pid = bid % BLOCKS_PER_CHANNEL; // pixel block index (within channel)
    int cid = bid / BLOCKS_PER_CHANNEL; // output channel index
    // compute block index in output pixel dimension
    int ofs = pid * THREADS_PER_BLOCK;
    // handle boundary
    if (tid >= ((ow * oh - ofs < THREADS_PER_BLOCK)? (ow * oh - ofs) : THREADS_PER_BLOCK)) return;
    // retrieve output pixel
    int w = (ofs + tid)/oh;
    int h = (ofs + tid)%oh;
    int w_ofs = w*sw;
    int h_ofs = h*sh;
    // apply pooling
    float v = -1e20;
    float input;
    int lw = (kw < iw-w_ofs)? kw : (iw-w_ofs);
    int lh = (kh < ih-h_ofs)? kh : (ih-h_ofs);
    for (int i=0; i<lw; i++){
        for (int j=0; j<lh; j++){
            int idx = INDEX_ROW_MAJOR_3(w_ofs+i,h_ofs+j,cid, iw,ih,oc);
            input = I[idx];
            v = ((input > v)? input : v);
        }
    }
    R[INDEX_ROW_MAJOR_3(w,h,cid, ow,oh,oc)] = v;
}
extern "C"
void max_pool(float * I, float * R, int iw, int ih, int kw, int kh, int sw, int sh, int ow, int oh, int oc) {
    float *dev_I, *dev_R;
    // I: (iw * ih * oc), row major ordered
    // R: (ow * oh * oc), row major ordered
    // todo: max-pooling
    // kernel function: pooling for a single sliding window
    // allocate the memory on the GPU
    cudaMalloc( (void**)&dev_I, iw * ih * oc * sizeof(float) );
    cudaMalloc( (void**)&dev_R, ow * oh * oc * sizeof(float) );
    // copy the arrays to the GPU
    cudaMemcpy( dev_I, I, iw * ih * oc * sizeof(float), cudaMemcpyHostToDevice );
    // within a block, thread over output pixels
    int BLOCKS_PER_CHANNEL = ceil(float(ow * oh)/float(THREADS_PER_BLOCK));
    mp<<<oc*BLOCKS_PER_CHANNEL,THREADS_PER_BLOCK>>>(dev_I, dev_R, iw, ih, kw, kh, sw, sh, ow, oh, oc);
    // copy the array back from the GPU to the CPU
    cudaMemcpy( R, dev_R, ow * oh * oc * sizeof(float), cudaMemcpyDeviceToHost );
    // cleanup
    cudaFree(dev_I); cudaFree(dev_R);
}
