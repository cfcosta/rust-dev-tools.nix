include!(concat!(env!("OUT_DIR"), "/generated.rs"));

pub fn message() -> String {
    format!(
        "app-before {} {} {}",
        rdt_shape_support::message(),
        GENERATED,
        rdt_shape_macro::marker!()
    )
}
