use nostr_sdk::prelude::PublicKey;
use parking_lot::RwLock;
use std::path::Path;
use std::sync::Arc;
use tracing::{info, warn};

const RUNTIME_FILE: &str = "whitelist_runtime.json";

/// Thread-safe shared whitelist that supports runtime modifications and persistence.
#[derive(Debug, Clone)]
pub struct Whitelist {
    inner: Arc<RwLock<Vec<PublicKey>>>,
}

impl Whitelist {
    /// Create a new whitelist from initial pubkeys, merging with any persisted runtime overrides.
    pub fn new(initial: Vec<PublicKey>, config_dir: Option<&Path>) -> Self {
        let mut pubkeys = initial;

        // Merge runtime overrides if they exist
        if let Some(dir) = config_dir {
            let runtime_path = dir.join(RUNTIME_FILE);
            if runtime_path.exists() {
                match std::fs::read_to_string(&runtime_path) {
                    Ok(contents) => match serde_json::from_str::<Vec<String>>(&contents) {
                        Ok(hex_keys) => {
                            for hex in &hex_keys {
                                if let Ok(pk) = PublicKey::from_hex(hex) {
                                    if !pubkeys.contains(&pk) {
                                        pubkeys.push(pk);
                                    }
                                }
                            }
                            info!(
                                "Loaded {} runtime whitelist overrides from {}",
                                hex_keys.len(),
                                runtime_path.display()
                            );
                        }
                        Err(e) => warn!("Failed to parse {}: {}", runtime_path.display(), e),
                    },
                    Err(e) => warn!("Failed to read {}: {}", runtime_path.display(), e),
                }
            }
        }

        Self {
            inner: Arc::new(RwLock::new(pubkeys)),
        }
    }

    /// Check if a pubkey is in the whitelist.
    pub fn contains(&self, pk: &PublicKey) -> bool {
        self.inner.read().contains(pk)
    }

    /// Check if the whitelist is empty (no restrictions).
    pub fn is_empty(&self) -> bool {
        self.inner.read().is_empty()
    }

    /// Return a snapshot of all whitelisted pubkeys.
    pub fn list(&self) -> Vec<PublicKey> {
        self.inner.read().clone()
    }

    /// Add a pubkey to the whitelist. Returns true if it was added (not already present).
    pub fn add(&self, pk: PublicKey) -> bool {
        let mut guard = self.inner.write();
        if guard.contains(&pk) {
            return false;
        }
        guard.push(pk);
        true
    }

    /// Remove a pubkey from the whitelist. Returns true if it was removed.
    pub fn remove(&self, pk: &PublicKey) -> bool {
        let mut guard = self.inner.write();
        let len_before = guard.len();
        guard.retain(|p| p != pk);
        guard.len() < len_before
    }

    /// Number of whitelisted pubkeys.
    pub fn len(&self) -> usize {
        self.inner.read().len()
    }

    /// Persist the current whitelist to `config/whitelist_runtime.json`.
    pub fn persist(&self, config_dir: &Path) -> Result<(), std::io::Error> {
        let hex_keys: Vec<String> = self.inner.read().iter().map(|pk| pk.to_hex()).collect();
        let json = serde_json::to_string_pretty(&hex_keys)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        let path = config_dir.join(RUNTIME_FILE);
        std::fs::write(&path, json)?;
        info!("Persisted {} whitelist entries to {}", hex_keys.len(), path.display());
        Ok(())
    }
}
