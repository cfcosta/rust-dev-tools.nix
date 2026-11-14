include!(concat!(env!("OUT_DIR"), "/value.rs"));

cfg_if::cfg_if! {
    if #[cfg(debug_assertions)] {
        pub const FAST_PROFILE: bool = true;
    } else {
        pub const FAST_PROFILE: bool = false;
    }
}

#[test]
fn generated_value_is_present() {
    assert!(!VALUE.is_empty());
}
