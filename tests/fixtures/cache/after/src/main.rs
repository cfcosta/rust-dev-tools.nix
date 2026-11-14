cfg_if::cfg_if! {
    if #[cfg(feature = "extra")] {
        const FEATURE: &str = "extra";
    } else {
        const FEATURE: &str = "default";
    }
}

fn main() {
    println!("after {FEATURE}");
}
