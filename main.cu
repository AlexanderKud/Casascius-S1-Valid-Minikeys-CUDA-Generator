/*
 * Casascius S1 Valid Minikeys CUDA Generator
 * Copyright (c) 2026 [OU$$@M@]
 * Licensed under MIT License
 */

#include <cuda.h>
#include <cuda_runtime.h>
#include <curand_kernel.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <windows.h>

// --- CONFIGURATION ---
#define THREADS 256
#define BLOCKS 2048
#define ITERATIONS_PER_KERNEL 1024
#define MAX_RESULTS 1048576

// Constantes SHA-256
__constant__ uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

__device__ __constant__ char B58[59] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

// Fonction hôte pour générer des caractères aléatoires
void rand58(char* p, int n){
    const char* b = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    for(int i=0; i<n; i++) p[i] = b[rand() % 58];
}

// Kernel d'initialisation RNG
__global__ void init_rng(curandState *states, unsigned long long seed, int offset) {
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    curand_init(seed + offset, id, 0, &states[id]);
}

// Fonction SHA256 Device optimisée
__device__ __forceinline__ bool check_sha256(const uint8_t* msg) {
    uint32_t h[8] = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    };
    uint32_t w[64];

    #pragma unroll
    for(int i=0; i<5; i++) {
        w[i] = ((uint32_t)msg[i*4] << 24) | ((uint32_t)msg[i*4+1] << 16) | 
               ((uint32_t)msg[i*4+2] << 8) | (uint32_t)msg[i*4+3];
    }
    w[5] = ((uint32_t)msg[20] << 24) | ((uint32_t)msg[21] << 16) | ((uint32_t)msg[22] << 8) | 0x80;
    
    #pragma unroll
    for(int i=6; i<15; i++) w[i] = 0;
    w[15] = 23 * 8; 

    #pragma unroll
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = ROTR(w[i - 15], 7) ^ ROTR(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ROTR(w[i - 2], 17) ^ ROTR(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh_var = h[7];

    #pragma unroll
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = ROTR(e, 6) ^ ROTR(e, 11) ^ ROTR(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = hh_var + S1 + ch + K[i] + w[i];
        uint32_t S0 = ROTR(a, 2) ^ ROTR(a, 13) ^ ROTR(a, 22);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + maj;

        hh_var = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }

    return ((h[0] + a) & 0xFF000000) == 0;
}

// Kernel principal
__global__ void keygen_kernel(char* outbuf, int* outcount, const char* YX_in, curandState *states){
    int id = blockIdx.x * blockDim.x + threadIdx.x;
    curandState localState = states[id];

    uint8_t key[24]; 
    key[0] = 'S';
    #pragma unroll
    for(int i=0; i<14; i++) key[1+i] = YX_in[i];
    key[22] = '?'; 

    for(int iter=0; iter < ITERATIONS_PER_KERNEL; iter++) {
        #pragma unroll
        for(int i=0; i<7; i++) key[15+i] = B58[curand(&localState) % 58];

        if (check_sha256(key)) {
            int idx = atomicAdd(outcount, 1);
            if (idx < MAX_RESULTS) {
                char* target = outbuf + idx * 22;
                #pragma unroll
                for(int k=0; k<22; k++) target[k] = key[k];
            }
        }
    }
    states[id] = localState;
}

// Fonction hôte
int main(int argc, char** argv) {
    // Optimisation I/O
    setvbuf(stdout, NULL, _IOFBF, 1024*1024*16);

    srand(time(NULL));

    // Gestion GPU
    int gpus[16];
    int num_gpus = 0;
    for(int i=1; i<argc; i++) {
        if(strcmp(argv[i], "-d") == 0 && i+1 < argc) {
            char* token = strtok(argv[i+1], ",");
            while(token != NULL) {
                gpus[num_gpus++] = atoi(token);
                token = strtok(NULL, ",");
            }
        }
    }
    if(num_gpus == 0) {
        gpus[0] = 0;
        num_gpus = 1;
    }

    // Initialisation RNG et constantes
    for(int i=0; i<num_gpus; i++) {
        cudaSetDevice(gpus[i]);
        curandState *d_states;
        char *d_YX;
        char *d_out;
        int *d_count;
        char *h_out;
        int *h_count;

        cudaMalloc(&d_states, BLOCKS * THREADS * sizeof(curandState));
        cudaMalloc(&d_YX, 14);
        cudaMalloc(&d_out, MAX_RESULTS * 22);
        cudaMalloc(&d_count, sizeof(int));
        cudaHostAlloc(&h_out, MAX_RESULTS * 22, cudaHostAllocDefault);
        cudaHostAlloc(&h_count, sizeof(int), cudaHostAllocDefault);

        init_rng<<<BLOCKS, THREADS>>>(d_states, time(NULL), i * 10000);
        cudaDeviceSynchronize();

        // Variables de gestion
        char Y[7], X[7];
        rand58(Y, 7); rand58(X, 7);
        char YX[14];
        memcpy(YX, Y, 7); memcpy(YX+7, X, 7);

        // Boucle principale
        while(true) {
            // Mise à jour pattern
            if(time(NULL) % 4 == 0) { rand58(Y, 7); }
            if(time(NULL) % 2 == 0) { rand58(X, 7); }
            memcpy(YX, Y, 7); memcpy(YX+7, X, 7);
            cudaMemcpy(d_YX, YX, 14, cudaMemcpyHostToDevice);

            cudaMemset(d_count, 0, sizeof(int));
            keygen_kernel<<<BLOCKS, THREADS>>>(d_out, d_count, d_YX, d_states);
            cudaDeviceSynchronize();

            int count;
            cudaMemcpy(&count, d_count, sizeof(int), cudaMemcpyDeviceToHost);
            if(count > 0) {
                if(count > MAX_RESULTS) count = MAX_RESULTS;
                cudaMemcpy(h_out, d_out, count * 22, cudaMemcpyDeviceToHost);
                for(int j=0; j<count; j++) {
                    fwrite(h_out + j*22, 1, 22, stdout);
                    fwrite("\n", 1, 1, stdout);
                }
            }
        }

        // Nettoyage
        cudaFree(d_states);
        cudaFree(d_YX);
        cudaFree(d_out);
        cudaFree(d_count);
        cudaFreeHost(h_out);
        cudaFreeHost(h_count);
    }
    return 0;
}

