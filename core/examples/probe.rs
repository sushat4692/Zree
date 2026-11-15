//! Smoke test against a real vault: `cargo run --release --example probe -- <vault>`
use zree_core::search::Index;
use zree_core::Vault;
use std::time::Instant;

fn main() {
    let root = std::env::args().nth(1).expect("usage: probe <vault-path>");
    let t0 = Instant::now();
    let vault = Vault::open(&root).unwrap();
    let notes = vault.list().unwrap();
    println!("notes: {} ({:.0?})", notes.len(), t0.elapsed());

    let t1 = Instant::now();
    let index = Index::build(&vault).unwrap();
    println!("index: {} entries ({:.0?})", index.len(), t1.elapsed());

    let tags = index.tags();
    let shown: usize = std::env::args()
        .nth(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(5);
    println!("tags: {} unique", tags.len());
    for t in tags.iter().take(shown) {
        println!("   #{} x{}", t.tag, t.count);
    }

    for q in ["採用", "メンタリング", "面談", "1on1", "formosa", "フォーム"] {
        let t = Instant::now();
        let hits = index.search(q, &[], 5);
        println!(
            "search {:>12}: {} hits ({:?}) top={:?}",
            q,
            hits.len(),
            t.elapsed(),
            hits.first().map(|h| (&h.title, h.score))
        );
    }

    let bytes: u64 = notes.iter().map(|n| n.bytes).sum();
    println!("total bytes: {:.0} KB", bytes as f64 / 1024.0);
}
