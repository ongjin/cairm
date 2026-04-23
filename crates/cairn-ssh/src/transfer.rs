use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[derive(Clone, Default)]
pub struct CancelFlag(Arc<AtomicBool>);

impl CancelFlag {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }

    pub fn cancel(&self) {
        self.0.store(true, Ordering::Relaxed);
    }
}

/// Callback hook for progress updates. Called from the transfer loop at
/// most once per 256 KiB chunk. Implementations should be cheap — FFI
/// callers typically post to a Swift actor.
pub type ProgressSink = Arc<dyn Fn(u64) + Send + Sync>;
