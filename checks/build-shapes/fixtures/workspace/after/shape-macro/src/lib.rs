use proc_macro::TokenStream;

#[proc_macro]
pub fn marker(_: TokenStream) -> TokenStream {
    "\"macro-after\"".parse().unwrap()
}
