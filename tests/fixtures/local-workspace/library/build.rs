fn main() {
    let value = std::fs::read_to_string("value.txt").unwrap();
    let out = std::env::var("OUT_DIR").unwrap();
    std::fs::write(
        format!("{out}/value.rs"),
        format!("pub const VALUE: &str = {value:?};"),
    )
    .unwrap();
    println!("cargo:rerun-if-changed=value.txt");
}
