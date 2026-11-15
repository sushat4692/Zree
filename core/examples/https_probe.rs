fn main() {
    let url = "https://github.com/sushat4692/Zree.git";
    let dest = "/tmp/zree-https-probe";
    let _ = std::fs::remove_dir_all(dest);
    match zree_core::git::Git::clone_into(url, std::path::Path::new(dest), &Default::default()) {
        Ok(_) => println!("HTTPS clone OK"),
        Err(e) => println!("HTTPS clone FAILED: {e}"),
    }
}
