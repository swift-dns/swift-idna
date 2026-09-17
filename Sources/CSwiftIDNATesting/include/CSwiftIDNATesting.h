#ifndef CSWIFT_DNS_IDNA_TESTING_H
#define CSWIFT_DNS_IDNA_TESTING_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char* source;
    const char* toUnicode;
    const char** toUnicodeStatus;
    size_t toUnicodeStatusCount;
    const char* toAsciiN;
    const char** toAsciiNStatus;
    size_t toAsciiNStatusCount;
} CSwiftIDNATestV2CCase;

const CSwiftIDNATestV2CCase *cswift_idna_test_v2_all_cases(size_t *count);

typedef struct {
    const char* c1;
    size_t c1Count;
    const char* c2;
    size_t c2Count;
    const char* c3;
    size_t c3Count;
    const char* c4;
    size_t c4Count;
    const char* c5;
    size_t c5Count;
    int part;
} CSwiftIDNANFCTestCCase;

const CSwiftIDNANFCTestCCase *cswift_idna_nfc_test_all_cases(size_t *count);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CSWIFT_DNS_IDNA_TESTING_H
