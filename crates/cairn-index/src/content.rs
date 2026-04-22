use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq)]
pub struct ContentHit {
    pub path_rel: String,
    pub line: u32,
    pub preview: String,
}

pub struct ContentSearch {
    handle: Option<std::thread::JoinHandle<()>>,
    cancel: Arc<AtomicBool>,
}

impl ContentSearch {
    pub fn spawn(
        rg_binary: &Path,
        root: &Path,
        pattern: &str,
        is_regex: bool,
        on_hit: impl Fn(ContentHit) + Send + 'static,
    ) -> Self {
        let cancel = Arc::new(AtomicBool::new(false));
        let cancel_thr = cancel.clone();
        let rg_path = rg_binary.to_path_buf();
        let root_path = root.to_path_buf();
        let pat = pattern.to_string();

        let handle = std::thread::spawn(move || {
            // ripgrep is regex-by-default; `-F` flips it to fixed-string
            // (literal) mode. Keeping the default off saves users from `*.tsx`
            // raising a regex parse error and silently returning zero hits.
            let mut cmd = Command::new(&rg_path);
            cmd.args(["--json", "--max-count", "200"]);
            if !is_regex {
                cmd.arg("-F");
            }
            cmd.arg(&pat).arg(&root_path);
            let mut child: Child = match cmd
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()
            {
                Ok(c) => c,
                Err(_) => return,
            };

            let stdout = match child.stdout.take() {
                Some(s) => s,
                None => {
                    let _ = child.kill();
                    return;
                }
            };
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                if cancel_thr.load(Ordering::SeqCst) {
                    let _ = child.kill();
                    break;
                }
                let line = match line {
                    Ok(l) => l,
                    Err(_) => continue,
                };
                let val: serde_json::Value = match serde_json::from_str(&line) {
                    Ok(v) => v,
                    Err(_) => continue,
                };
                if val["type"] != "match" {
                    continue;
                }
                let data = &val["data"];
                let path = data["path"]["text"].as_str().unwrap_or("").to_string();
                let line_num = data["line_number"].as_u64().unwrap_or(0) as u32;
                let preview = data["lines"]["text"]
                    .as_str()
                    .unwrap_or("")
                    .trim_end()
                    .to_string();
                let rel = match Path::new(&path).strip_prefix(&root_path) {
                    Ok(r) => r.to_string_lossy().into_owned(),
                    Err(_) => path,
                };
                on_hit(ContentHit {
                    path_rel: rel,
                    line: line_num,
                    preview,
                });
            }
            let _ = child.wait();
        });

        Self {
            handle: Some(handle),
            cancel,
        }
    }

    pub fn cancel(&mut self) {
        self.cancel.store(true, Ordering::SeqCst);
    }
}

impl Drop for ContentSearch {
    fn drop(&mut self) {
        self.cancel.store(true, Ordering::SeqCst);
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use tempfile::TempDir;

    fn which_rg() -> Option<std::path::PathBuf> {
        let out = std::process::Command::new("which")
            .arg("rg")
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        let s = String::from_utf8(out.stdout).ok()?;
        let trimmed = s.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.into())
        }
    }

    #[test]
    fn finds_hits_in_tmp_dir() {
        let rg = match which_rg() {
            Some(p) => p,
            None => {
                eprintln!("skip: rg not installed");
                return;
            }
        };
        let tmp = TempDir::new().unwrap();
        fs::write(tmp.path().join("a.txt"), "hello world\nfoo bar\n").unwrap();

        let counter = Arc::new(AtomicUsize::new(0));
        let c = counter.clone();
        let search = ContentSearch::spawn(&rg, tmp.path(), "hello", false, move |_| {
            c.fetch_add(1, Ordering::SeqCst);
        });
        std::thread::sleep(std::time::Duration::from_millis(500));
        drop(search); // joins
        assert_eq!(counter.load(Ordering::SeqCst), 1);
    }
}
