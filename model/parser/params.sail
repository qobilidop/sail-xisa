
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
