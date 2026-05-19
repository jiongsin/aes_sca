#include <iostream>
#include <stdint.h>
#include <string.h>
#include "svdpi.h"

const uint8_t sbox[256] = {
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
};

const uint8_t Rcon[11] = {0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36};

uint8_t xtime(uint8_t x) {
    return (x << 1) ^ (((x >> 7) & 1) ? 0x1b : 0x00);
}

void mix_columns(uint8_t* state) {
    for (int i = 0; i < 4; i++) {
        uint8_t a = state[i*4 + 0], b = state[i*4 + 1], c = state[i*4 + 2], d = state[i*4 + 3];
        state[i*4 + 0] = xtime(a ^ b) ^ b ^ c ^ d;
        state[i*4 + 1] = xtime(b ^ c) ^ c ^ d ^ a;
        state[i*4 + 2] = xtime(c ^ d) ^ d ^ a ^ b;
        state[i*4 + 3] = xtime(d ^ a) ^ a ^ b ^ c;
    }
}

void shift_rows(uint8_t* state) {
    uint8_t tmp;
    tmp = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = tmp;
    tmp = state[2]; state[2] = state[10]; state[10] = tmp; tmp = state[6]; state[6] = state[14]; state[14] = tmp;
    tmp = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = tmp;
}

void aes_encrypt_core(int mode, const uint8_t* key_in, const uint8_t* data_in, uint8_t* data_out) {
    uint8_t state[16];
    uint8_t round_key[240]; 
    
    int Nk = mode / 32; 
    int Nr = (Nk == 8) ? 14 : (Nk == 6) ? 12 : 10;

    for (int i = 0; i < 16; i++) {
        state[i] = data_in[i];
    }

    for (int i = 0; i < Nk * 4; i++) {
        round_key[i] = key_in[i];
    }

    for (int i = Nk; i < 4 * (Nr + 1); i++) {
        uint8_t temp[4];
        for (int j = 0; j < 4; j++) temp[j] = round_key[(i-1)*4 + j];
        
        if (i % Nk == 0) {
            uint8_t k = temp[0];
            temp[0] = sbox[temp[1]] ^ Rcon[i/Nk];
            temp[1] = sbox[temp[2]];
            temp[2] = sbox[temp[3]];
            temp[3] = sbox[k];
        } else if (Nk > 6 && i % Nk == 4) {
            for (int j = 0; j < 4; j++) temp[j] = sbox[temp[j]];
        }
        for (int j = 0; j < 4; j++) round_key[i*4+j] = round_key[(i-Nk)*4 + j] ^ temp[j];
    }

    for (int i = 0; i < 16; i++) state[i] ^= round_key[i];

    for (int r = 1; r < Nr; r++) {
        for (int i = 0; i < 16; i++) state[i] = sbox[state[i]];
        shift_rows(state);
        mix_columns(state);
        for (int i = 0; i < 16; i++) state[i] ^= round_key[r*16 + i];
    }

    for (int i = 0; i < 16; i++) state[i] = sbox[state[i]];
    shift_rows(state);
    for (int i = 0; i < 16; i++) state[i] ^= round_key[Nr*16 + i];

    for (int i = 0; i < 16; i++) {
        data_out[i] = state[i];
    }
}

extern "C" uint8_t aes_sbox_ref_model(uint8_t data_in) {
    return sbox[data_in];
}

extern "C" void aes_operation_ref_model(int mode, const uint32_t* key_in, const uint32_t* data_in, uint32_t* data_out) {
    uint8_t state[16];
    uint8_t key[32];
    uint8_t out[16];
    
    int Nk = mode / 32; 

    for (int i = 0; i < 4; i++) {
        state[i*4+0] = (data_in[i] >> 0)  & 0xFF;
        state[i*4+1] = (data_in[i] >> 8)  & 0xFF;
        state[i*4+2] = (data_in[i] >> 16) & 0xFF;
        state[i*4+3] = (data_in[i] >> 24) & 0xFF;
    }

    for (int i = 0; i < Nk; i++) {
        key[i*4+0] = (key_in[i] >> 0)  & 0xFF;
        key[i*4+1] = (key_in[i] >> 8)  & 0xFF;
        key[i*4+2] = (key_in[i] >> 16) & 0xFF;
        key[i*4+3] = (key_in[i] >> 24) & 0xFF;
    }

    aes_encrypt_core(mode, key, state, out);

    for (int i = 0; i < 4; i++) {
        data_out[i] = (out[i*4+3] << 24) | (out[i*4+2] << 16) | (out[i*4+1] << 8) | out[i*4+0];
    }
}

extern "C" void aes_ctr_ref_model(int mode, const uint32_t* key_in, const uint32_t* nonce_in, const uint32_t* pt_in, uint32_t* ct_out) {
    uint8_t key[32];
    uint8_t nonce1[16];
    uint8_t nonce2[16];
    uint8_t enc_nonce1[16];
    uint8_t enc_nonce2[16];
    uint8_t pt[32];
    uint8_t ct[32];

    int Nk = mode / 32;

    for (int i = 0; i < Nk; i++) {
        key[i*4+0] = (key_in[i] >> 0)  & 0xFF;
        key[i*4+1] = (key_in[i] >> 8)  & 0xFF;
        key[i*4+2] = (key_in[i] >> 16) & 0xFF;
        key[i*4+3] = (key_in[i] >> 24) & 0xFF;
    }

    for (int i = 0; i < 4; i++) {
        nonce1[i*4+0] = (nonce_in[i] >> 0)  & 0xFF;
        nonce1[i*4+1] = (nonce_in[i] >> 8)  & 0xFF;
        nonce1[i*4+2] = (nonce_in[i] >> 16) & 0xFF;
        nonce1[i*4+3] = (nonce_in[i] >> 24) & 0xFF;
    }
    
    for (int i = 0; i < 16; i++) {
        nonce2[i] = nonce1[i];
    }
    
    uint32_t nonce_lsb = nonce_in[3];
    nonce_lsb += 1; 
    nonce2[12] = (nonce_lsb >> 0)  & 0xFF;
    nonce2[13] = (nonce_lsb >> 8)  & 0xFF;
    nonce2[14] = (nonce_lsb >> 16) & 0xFF;
    nonce2[15] = (nonce_lsb >> 24) & 0xFF;

    for (int i = 0; i < 8; i++) {
        pt[i*4+0] = (pt_in[i] >> 0)  & 0xFF;
        pt[i*4+1] = (pt_in[i] >> 8)  & 0xFF;
        pt[i*4+2] = (pt_in[i] >> 16) & 0xFF;
        pt[i*4+3] = (pt_in[i] >> 24) & 0xFF;
    }

    aes_encrypt_core(mode, key, nonce1, enc_nonce1);
    aes_encrypt_core(mode, key, nonce2, enc_nonce2);

    for (int i = 0; i < 16; i++) {
        ct[i] = pt[i] ^ enc_nonce1[i];
        ct[16+i] = pt[16+i] ^ enc_nonce2[i];
    }

    for (int i = 0; i < 8; i++) {
        ct_out[i] = (ct[i*4+3] << 24) | (ct[i*4+2] << 16) | (ct[i*4+1] << 8) | ct[i*4+0];
    }
}
