include!(concat!(env!("OUT_DIR"), "/generated.rs"));

pub fn message() -> String {
    format!(
        "app-after {} {} {}",
        rdt_shape_support::message(),
        GENERATED,
        rdt_shape_macro::marker!()
    )
}
