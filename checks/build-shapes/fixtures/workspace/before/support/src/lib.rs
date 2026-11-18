cfg_if::cfg_if! {
    if #[cfg(target_pointer_width = "64")] {
        pub fn message() -> &'static str { "support-before" }
    } else {
        compile_error!("the shape fixtures target the supported 64-bit platforms");
    }
}

#[cfg(test)]
mod tests {
    // Set only by the package-selection check, which runs the tests under
    // nextest with a check-only tool on PATH.
    #[test]
    fn runs_where_the_check_asks() {
        if std::env::var_os("RDT_EXPECT_NEXTEST").is_none() {
            return;
        }
        assert_eq!(std::env::var("NEXTEST").as_deref(), Ok("1"));
        let tool = std::process::Command::new("rdt-check-tool").output().unwrap();
        assert_eq!(tool.stdout, b"check");
    }
}
