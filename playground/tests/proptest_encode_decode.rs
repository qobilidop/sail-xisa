mod common;

use proptest::prelude::*;
use xisa::decode::decode;
use xisa::encode::encode;

proptest! {
    #[test]
    fn encode_decode_roundtrip(instr in common::arb_instruction()) {
        let word = encode(&instr);
        let decoded = decode(word).expect("decode failed for a valid encoded instruction");
        prop_assert_eq!(decoded, instr);
    }
}
