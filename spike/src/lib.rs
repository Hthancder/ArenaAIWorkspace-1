//! Phần **logic** của spec, viết bằng Rust, **0 dependency** (§56.1).
//!
//! Mỗi module ở đây là một chương spec biến thành thứ chạy được và test được
//! ngoài môi trường thật — đó là toàn bộ lý do crate này tồn tại.

pub mod machine;
pub mod pipeline;
pub mod policy;
pub mod security;

/// Câu trả lời cho "code khác spec ở đâu" — xem [`security::DEVIATIONS`].
pub use security::DEVIATIONS;
