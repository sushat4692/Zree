//! Measures the tag suggester against a real vault.
//!
//!     cargo run --release --example tag_quality -- /path/to/vault
//!
//! Every note that already carries tags is asked to guess them with the tags hidden, which is
//! exactly the situation of an untagged note. Precision is what matters for suggestions —
//! a wrong chip costs the author a tap, so the rule layer aims high and stays quiet otherwise.

use std::collections::HashMap;
use zree_core::{suggest, Index, Vault};

fn main() {
    let root = std::env::args().nth(1).expect("usage: tag_quality <vault>");
    let vault = Vault::open(&root).expect("vault");
    let index = Index::build(&vault).expect("index");

    let tagged: Vec<&zree_core::search::Entry> =
        index.entries.iter().filter(|e| !e.meta.tags.is_empty()).collect();
    let untagged = index.entries.len() - tagged.len();
    println!("notes {} / tagged {} / untagged {}", index.entries.len(), tagged.len(), untagged);
    println!("vocabulary {} tags", index.vocab.counts.len());

    for tier_limit in [1u8, 2] {
        let (mut tp, mut fp, mut fn_, mut hit1, mut shown) = (0usize, 0usize, 0usize, 0usize, 0usize);
        for entry in &tagged {
            let picked: Vec<String> = suggest::suggest(
                &index,
                &entry.meta.id,
                &entry.meta.title,
                &entry.body,
                &[],
                5,
            )
            .into_iter()
            .filter(|s| s.tier <= tier_limit)
            .map(|s| zree_core::search::normalize(&s.tag))
            .collect();
            let real: Vec<String> =
                entry.meta.tags.iter().map(|t| zree_core::search::normalize(t)).collect();
            if !picked.is_empty() {
                shown += 1;
            }
            if picked.first().is_some_and(|p| real.contains(p)) {
                hit1 += 1;
            }
            for p in &picked {
                if real.contains(p) {
                    tp += 1
                } else {
                    fp += 1
                }
            }
            for r in &real {
                if !picked.contains(r) {
                    fn_ += 1
                }
            }
        }
        let n = tagged.len() as f64;
        let precision = tp as f64 / ((tp + fp) as f64).max(1.0);
        let recall = tp as f64 / ((tp + fn_) as f64).max(1.0);
        println!(
            "tier<= {tier_limit}: P={:.0}% R={:.0}% P@1={:.0}%  shown {}/{}",
            precision * 100.0,
            recall * 100.0,
            hit1 as f64 / n * 100.0,
            shown,
            tagged.len()
        );
    }

    let mut by_reason: HashMap<&str, (usize, usize)> = HashMap::new();
    for entry in &tagged {
        let real: Vec<String> =
            entry.meta.tags.iter().map(|t| zree_core::search::normalize(t)).collect();
        for s in suggest::suggest(&index, &entry.meta.id, &entry.meta.title, &entry.body, &[], 5) {
            let correct = real.contains(&zree_core::search::normalize(&s.tag));
            for reason in &s.reasons {
                let slot = by_reason.entry(reason.as_str()).or_insert((0, 0));
                slot.1 += 1;
                if correct {
                    slot.0 += 1;
                }
            }
        }
    }
    let mut rows: Vec<_> = by_reason.into_iter().collect();
    rows.sort_by_key(|(_, (hit, total))| std::cmp::Reverse(*total - *hit + *total));
    println!("\nreason            correct / shown");
    for (reason, (hit, total)) in rows {
        println!("{reason:<16} {hit:>4} / {total:<4} = {:.0}%", hit as f64 / total as f64 * 100.0);
    }

    let covered = index
        .entries
        .iter()
        .filter(|e| e.meta.tags.is_empty())
        .filter(|e| {
            !suggest::suggest(&index, &e.meta.id, &e.meta.title, &e.body, &[], 3)
                .iter()
                .filter(|s| s.tier == 1)
                .collect::<Vec<_>>()
                .is_empty()
        })
        .count();
    println!("\nuntagged notes with a tier-1 suggestion: {covered}");
}
