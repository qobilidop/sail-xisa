
// Implementation-chosen parameters for the parser model.
// The XISA spec defines interfaces but not capacities — these are
// implementation-defined. See docs/modeling-decisions.md.

// Transition table: 64 entries.
// Each rule maps (state, protocol_key) -> (next_state_pc, next_state).
// The spec does not define table capacity or state-ID bit width.
//
// Parameters:
//   Table size:      64 entries (indexed 0-63)
//   State ID:        8 bits (bits8), range 0-255
//   Protocol key:    24 bits (bits24), max size per NXTP spec
//   PC entry point:  16 bits (bits16), matching ppc width
//
// Sail requires literal sizes in vector declarations, so these
// parameters are documented here and used as literals elsewhere.
// Update both this file and the declarations if changing sizes.

// PSEEK table: 32 entries.
// Each entry defines a skippable protocol header.
// The spec does not define table capacity or entry field widths.
//
// Parameters:
//   Table size:         32 entries (indexed 0-31)
//   Class ID:           8 bits (bits8), range 0-3 per spec
//   Protocol value:     16 bits (bits16), max from SizeBits range 1-16
//   Header length:      8 bits (bits8), fixed bytes per entry
//   Next proto offset:  8 bits (bits8), byte offset within header
//   Next proto size:    8 bits (bits8), size in bits
//
// See docs/specs/2026-04-01-pseek-design.md for assumptions.
