use smallvec::SmallVec;

// Growing a SmallVec and sorting instantiate generic code whose panics name
// their source files: one in the vendored smallvec, one in core's rust-src.
fn main() {
    let mut values: SmallVec<[u64; 2]> = std::env::args().map(|arg| arg.len() as u64).collect();
    values.extend([3, 1, 2]);
    values.sort();
    println!("{}", values.len());
}
