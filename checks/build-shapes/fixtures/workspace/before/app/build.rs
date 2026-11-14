use std::{env, fs, path::PathBuf, process::Command};

fn main() {
    assert_eq!(env::var("RDT_SHAPE_BUILD_VALUE").unwrap(), "configured");
    let tool = Command::new("rdt-shape-tool").output().unwrap();
    assert!(tool.status.success());
    assert_eq!(tool.stdout, b"native");
    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("generated.rs");
    fs::write(
        output,
        "pub const GENERATED: &str = \"generated-before\";\n",
    )
    .unwrap();
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=RDT_SHAPE_BUILD_VALUE");
}
