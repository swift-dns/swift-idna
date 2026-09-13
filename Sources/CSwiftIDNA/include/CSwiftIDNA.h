#ifndef CSWIFT_DNS_IDNA_H
#define CSWIFT_DNS_IDNA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// IDNA mapping is stored as a two-stage code-point trie built by
// utils/IDNAMappingTableGenerator.swift.
//
// A code point is split into a block number (high bits) and an offset within
// the block (low bits). `block_offsets` maps the block number to where that
// block's values begin in `packed_values`:
//
//   packed_value = packed_values[block_offsets[cp >> BLOCK_SHIFT] + (cp & BLOCK_MASK)]
//
// The top 3 bits of `packed_value` are the mapping tag; the low 13 bits are the
// payload. For the mapped and deviation tags the payload indexes `mapped_slices`,
// each of which packs a byte offset into `mapped_utf8` (high 24 bits) and a
// length (low 8 bits). The other tags carry no payload. The tag values are
// defined by the `Tag` enum in Sources/SwiftIDNA/IDNAMapping.swift.

#define CSWIFT_IDNA_BLOCK_SHIFT 6
#define CSWIFT_IDNA_BLOCK_MASK 63

extern const uint16_t cswift_idna_block_offsets[];
extern const uint16_t cswift_idna_packed_values[];
extern const uint32_t cswift_idna_mapped_slices[];
extern const uint8_t cswift_idna_mapped_utf8[];

// Returns the packed 16-bit trie value for any given valid Unicode scalar value.
static inline uint16_t cswift_idna_packed_value(uint32_t code_point) {
    return cswift_idna_packed_values[
        (uint32_t)cswift_idna_block_offsets[code_point >> CSWIFT_IDNA_BLOCK_SHIFT]
        + (code_point & CSWIFT_IDNA_BLOCK_MASK)
    ];
}

// Returns the packed mapped/deviation slice (byte offset into mapped_utf8 in the
// high 24 bits, UTF-8 byte length in the low 8 bits) for a mapped/deviation payload.
static inline uint32_t cswift_idna_mapped_slice(uint32_t slice_index) {
    return cswift_idna_mapped_slices[slice_index];
}

// Returns a pointer to the mapped/deviation UTF-8 bytes at the given byte offset.
static inline const uint8_t *cswift_idna_mapped_utf8_at(uint32_t byte_offset) {
    return cswift_idna_mapped_utf8 + byte_offset;
}

// NFC normalization data is stored as a two-stage code-point trie built by
// utils/NFCTableGenerator.swift, in the same shape as the IDNA mapping trie above,
// plus a decomposition blob and a sorted canonical-composition pair table.
//
// Code points at or above NFC_TRIE_LIMIT carry no normalization data and are inert;
// the trie only covers code points below the limit.
//
// The top 3 bits of a packed value are the normalization tag; the low 13 bits are the
// payload: the scalar's canonical combining class for the ccc-carrying tags, or an
// index into `nfc_decomposition_slices` for the decomposing tags. Each slice packs an
// element offset into `nfc_decomposition_scalars` (high 24 bits) and an element count
// (low 8 bits). Each decomposition scalar packs a canonical combining class (bits 21+)
// and a scalar value (low 21 bits). Each composition pair packs the first scalar
// (bits 43+), the second scalar (bits 22+), and the composite scalar (low 22 bits),
// sorted for binary search on the high 42 bits. The tag values are defined by the
// `Tag` enum in Sources/SwiftIDNA/NFCNormalization.swift.

#define CSWIFT_IDNA_NFC_TRIE_LIMIT 0x30000
#define CSWIFT_IDNA_NFC_BLOCK_SHIFT 6
#define CSWIFT_IDNA_NFC_BLOCK_MASK 63

extern const uint16_t cswift_idna_nfc_block_offsets[];
extern const uint16_t cswift_idna_nfc_packed_values[];
extern const uint32_t cswift_idna_nfc_decomposition_slices[];
extern const uint32_t cswift_idna_nfc_decomposition_scalars[];
extern const uint64_t cswift_idna_nfc_composition_pairs[];
extern const int32_t cswift_idna_nfc_composition_pairs_count;

// Returns the packed 16-bit normalization trie value for any given valid Unicode scalar value.
static inline uint16_t cswift_idna_nfc_value(uint32_t code_point) {
    if (code_point >= CSWIFT_IDNA_NFC_TRIE_LIMIT) {
        return 0;
    }
    return cswift_idna_nfc_packed_values[
        (uint32_t)cswift_idna_nfc_block_offsets[code_point >> CSWIFT_IDNA_NFC_BLOCK_SHIFT]
        + (code_point & CSWIFT_IDNA_NFC_BLOCK_MASK)
    ];
}

// Returns the packed decomposition slice (element offset into nfc_decomposition_scalars in
// the high 24 bits, element count in the low 8 bits) for a decomposing payload.
static inline uint32_t cswift_idna_nfc_decomposition_slice(uint32_t slice_index) {
    return cswift_idna_nfc_decomposition_slices[slice_index];
}

// Returns the packed decomposition scalar (canonical combining class in bits 21+,
// scalar value in the low 21 bits) at the given element offset.
static inline uint32_t cswift_idna_nfc_decomposition_scalar_at(uint32_t element_offset) {
    return cswift_idna_nfc_decomposition_scalars[element_offset];
}

// Returns the packed composition pair at the given index.
static inline uint64_t cswift_idna_nfc_composition_pair(int32_t index) {
    return cswift_idna_nfc_composition_pairs[index];
}

#ifdef __cplusplus
} // extern "C"
#endif

#endif // CSWIFT_DNS_IDNA_H
