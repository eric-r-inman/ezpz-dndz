//! Re-export of foundation's `LogLevel` / `LogFormat` types.
//!
//! Kept as a stable import path for the rest of the workspace
//! (`use ezpz_dndz_lib::{LogLevel, LogFormat};`).  All actual
//! definitions, parsing, `Display`, and `tracing::Level` conversion
//! live in `rust_template_foundation::logging`.

pub use rust_template_foundation::logging::{
  LogFormat, LogFormatParseError, LogLevel, LogLevelParseError,
};
