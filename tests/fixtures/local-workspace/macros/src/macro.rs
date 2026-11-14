extern crate proc_macro;

#[proc_macro]
pub fn forty_two(_: proc_macro::TokenStream) -> proc_macro::TokenStream {
    "42".parse().unwrap()
}
