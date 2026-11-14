cfg_if::cfg_if! {
    if #[cfg(target_pointer_width = "64")] {
        pub fn message() -> &'static str { "library-after" }
    } else {
        compile_error!("the shape fixtures target the supported 64-bit platforms");
    }
}
