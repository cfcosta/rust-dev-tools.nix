fn main() {
    assert!(
        local_library::FAST_PROFILE,
        "the custom profile must enable debug assertions"
    );
    println!("{} {}", local_library::VALUE, local_macros::forty_two!());
}
