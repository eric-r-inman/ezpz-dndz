//! Hex digests the server stores and compares.

use sha2::{Digest, Sha256};

/// The SHA-256 of `bytes` as lowercase hex.
///
/// sha2's digest implements no hex formatting of its own.  A
/// compendium content hash already on disk has to keep matching, so
/// the output must not change shape.
pub fn sha256_hex(bytes: &[u8]) -> String {
  Sha256::digest(bytes)
    .iter()
    .map(|byte| format!("{byte:02x}"))
    .collect()
}

#[cfg(test)]
mod tests {
  use super::sha256_hex;

  // FIPS 180-2's first SHA-256 example.  Stored content hashes take
  // exactly this lowercase-hex form, so a change of shape here would
  // mark every bundled creature as edited.
  #[test]
  fn sha256_hex_matches_the_standard_vector() {
    assert_eq!(
      sha256_hex(b"abc"),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
  }
}
