use crate::server::ServerState;
use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    routing::{delete, get, post},
    Json, Router,
};
use nostr_sdk::prelude::*;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use tracing::{debug, warn};

// --- Types ---

#[derive(Clone)]
#[allow(dead_code)]
pub(crate) struct AdminState {
    admin_pubkeys: Vec<PublicKey>,
    sessions: Arc<RwLock<HashMap<String, Session>>>,
    challenges: Arc<RwLock<HashMap<String, ChallengeRecord>>>,
    relay_url: String,
}

pub(crate) struct Session {
    _pubkey: PublicKey,
    expires_at: std::time::Instant,
}

pub(crate) struct ChallengeRecord {
    _challenge: String,
    created_at: std::time::Instant,
}

#[derive(Serialize)]
struct ChallengeResponse {
    challenge: String,
}

#[derive(Deserialize)]
struct AuthRequest {
    signed_event: serde_json::Value,
}

#[derive(Serialize)]
struct AuthResponse {
    token: String,
}

#[derive(Serialize)]
struct ErrorResponse {
    error: String,
}

#[derive(Deserialize)]
struct AddWhitelistRequest {
    pubkey: String,
}

#[derive(Serialize)]
struct WhitelistEntry {
    hex: String,
    npub: String,
}

#[derive(Serialize)]
struct GroupInfo {
    id: String,
    name: String,
    about: Option<String>,
    member_count: usize,
    private: bool,
    closed: bool,
    broadcast: bool,
}

#[derive(Serialize)]
struct StatsResponse {
    active_connections: usize,
    total_groups: usize,
    total_members: usize,
    whitelisted_count: usize,
    uptime_seconds: u64,
}

#[derive(Serialize)]
pub struct RelayInfoResponse {
    pub name: String,
    pub description: String,
    pub group_count: usize,
    pub supported_nips: Vec<u16>,
}

#[derive(Serialize)]
struct SessionCheckResponse {
    valid: bool,
    pubkey: Option<String>,
}

// --- Helper: generate random hex ---

fn random_hex(bytes: usize) -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let random_bytes: Vec<u8> = (0..bytes).map(|_| rng.gen()).collect();
    random_bytes.iter().map(|b| format!("{b:02x}")).collect()
}

// --- Auth helpers ---

fn extract_bearer_token(headers: &HeaderMap) -> Option<String> {
    headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(|s| s.to_string())
}

fn validate_session(admin_state: &AdminState, headers: &HeaderMap) -> Option<PublicKey> {
    let token = extract_bearer_token(headers)?;
    let sessions = admin_state.sessions.read();
    let session = sessions.get(&token)?;
    if session.expires_at > std::time::Instant::now() {
        Some(session._pubkey)
    } else {
        None
    }
}

fn unauthorized() -> (StatusCode, Json<ErrorResponse>) {
    (
        StatusCode::UNAUTHORIZED,
        Json(ErrorResponse {
            error: "Unauthorized".to_string(),
        }),
    )
}

// --- Routes ---

pub fn admin_routes() -> Router<Arc<ServerState>> {
    Router::new()
        .route("/challenge", get(handle_challenge))
        .route("/auth", post(handle_auth))
        .route("/session", get(handle_session_check))
        .route("/whitelist", get(handle_whitelist_list))
        .route("/whitelist", post(handle_whitelist_add))
        .route("/whitelist/{hex}", delete(handle_whitelist_remove))
        .route("/groups", get(handle_groups))
        .route("/stats", get(handle_stats))
}

pub fn public_api_routes() -> Router<Arc<ServerState>> {
    Router::new().route("/relay-info", get(handle_relay_info))
}

// --- Handlers ---

async fn handle_challenge(
    State(state): State<Arc<ServerState>>,
) -> impl IntoResponse {
    let challenge = random_hex(32);
    let admin_state = get_admin_state(&state);

    admin_state.challenges.write().insert(
        challenge.clone(),
        ChallengeRecord {
            _challenge: challenge.clone(),
            created_at: std::time::Instant::now(),
        },
    );

    // Clean up old challenges (older than 5 minutes)
    let cutoff = std::time::Instant::now() - std::time::Duration::from_secs(300);
    admin_state
        .challenges
        .write()
        .retain(|_, v| v.created_at > cutoff);

    Json(ChallengeResponse { challenge })
}

async fn handle_auth(
    State(state): State<Arc<ServerState>>,
    Json(req): Json<AuthRequest>,
) -> impl IntoResponse {
    let admin_state = get_admin_state(&state);

    // Parse the signed event
    let json_str = serde_json::to_string(&req.signed_event).unwrap_or_default();
    let event: Event = match Event::from_json(&json_str) {
        Ok(e) => e,
        Err(e) => {
            warn!("Admin auth: invalid event: {}", e);
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "Invalid event".to_string(),
                }),
            ));
        }
    };

    // Verify it's kind 22242 (NIP-42 AUTH)
    if event.kind != Kind::from(22242) {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Event must be kind 22242".to_string(),
            }),
        ));
    }

    // Verify signature
    if event.verify().is_err() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Invalid signature".to_string(),
            }),
        ));
    }

    // Check pubkey is an admin
    if !admin_state.admin_pubkeys.contains(&event.pubkey) {
        return Err((
            StatusCode::FORBIDDEN,
            Json(ErrorResponse {
                error: "Not an admin pubkey".to_string(),
            }),
        ));
    }

    // Extract and verify challenge from tags
    let challenge_tag = event.tags.iter().find(|t| {
        t.as_slice().first().map(|s| s.as_str()) == Some("challenge")
    });

    let challenge = match challenge_tag {
        Some(tag) => match tag.as_slice().get(1) {
            Some(c) => c.to_string(),
            None => {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        error: "Missing challenge value in tag".to_string(),
                    }),
                ));
            }
        },
        None => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "Missing challenge tag".to_string(),
                }),
            ));
        }
    };

    // Verify challenge exists and was recently issued
    {
        let mut challenges = admin_state.challenges.write();
        match challenges.remove(&challenge) {
            Some(record) => {
                let age = record.created_at.elapsed();
                if age > std::time::Duration::from_secs(300) {
                    return Err((
                        StatusCode::BAD_REQUEST,
                        Json(ErrorResponse {
                            error: "Challenge expired".to_string(),
                        }),
                    ));
                }
            }
            None => {
                return Err((
                    StatusCode::BAD_REQUEST,
                    Json(ErrorResponse {
                        error: "Unknown or already used challenge".to_string(),
                    }),
                ));
            }
        }
    }

    // Create session token (4 hour TTL)
    let token = random_hex(32);
    admin_state.sessions.write().insert(
        token.clone(),
        Session {
            _pubkey: event.pubkey,
            expires_at: std::time::Instant::now() + std::time::Duration::from_secs(4 * 3600),
        },
    );

    // Clean up expired sessions
    let now = std::time::Instant::now();
    admin_state
        .sessions
        .write()
        .retain(|_, v| v.expires_at > now);

    debug!("Admin authenticated: {}", event.pubkey);
    Ok(Json(AuthResponse { token }))
}

async fn handle_session_check(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let admin_state = get_admin_state(&state);
    match validate_session(&admin_state, &headers) {
        Some(pk) => Json(SessionCheckResponse {
            valid: true,
            pubkey: Some(pk.to_hex()),
        }),
        None => Json(SessionCheckResponse {
            valid: false,
            pubkey: None,
        }),
    }
}

async fn handle_whitelist_list(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    let admin_state = get_admin_state(&state);
    if validate_session(&admin_state, &headers).is_none() {
        return Err(unauthorized());
    }

    let entries: Vec<WhitelistEntry> = state
        .whitelist
        .list()
        .iter()
        .map(|pk| WhitelistEntry {
            hex: pk.to_hex(),
            npub: pk.to_bech32().unwrap_or_default(),
        })
        .collect();

    Ok(Json(entries))
}

async fn handle_whitelist_add(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
    Json(req): Json<AddWhitelistRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    let admin_state = get_admin_state(&state);
    if validate_session(&admin_state, &headers).is_none() {
        return Err(unauthorized());
    }

    // Try to parse as npub first, then hex
    let pk = if req.pubkey.starts_with("npub") {
        PublicKey::from_bech32(&req.pubkey).map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "Invalid npub".to_string(),
                }),
            )
        })?
    } else {
        PublicKey::from_hex(&req.pubkey).map_err(|_| {
            (
                StatusCode::BAD_REQUEST,
                Json(ErrorResponse {
                    error: "Invalid hex pubkey".to_string(),
                }),
            )
        })?
    };

    let added = state.whitelist.add(pk);
    if added {
        if let Err(e) = state.whitelist.persist(std::path::Path::new(&state.config_dir)) {
            warn!("Failed to persist whitelist: {}", e);
        }
    }

    Ok((
        StatusCode::OK,
        Json(WhitelistEntry {
            hex: pk.to_hex(),
            npub: pk.to_bech32().unwrap_or_default(),
        }),
    ))
}

async fn handle_whitelist_remove(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
    Path(hex): Path<String>,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    let admin_state = get_admin_state(&state);
    if validate_session(&admin_state, &headers).is_none() {
        return Err(unauthorized());
    }

    let pk = PublicKey::from_hex(&hex).map_err(|_| {
        (
            StatusCode::BAD_REQUEST,
            Json(ErrorResponse {
                error: "Invalid hex pubkey".to_string(),
            }),
        )
    })?;

    let removed = state.whitelist.remove(&pk);
    if removed {
        if let Err(e) = state.whitelist.persist(std::path::Path::new(&state.config_dir)) {
            warn!("Failed to persist whitelist: {}", e);
        }
    }

    Ok(StatusCode::NO_CONTENT)
}

async fn handle_groups(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    let admin_state = get_admin_state(&state);
    if validate_session(&admin_state, &headers).is_none() {
        return Err(unauthorized());
    }

    let groups = &state.http_state.groups;
    let mut result = Vec::new();

    for entry in groups.iter() {
        let ((_, id), group) = (entry.key(), entry.value());
        result.push(GroupInfo {
            id: id.clone(),
            name: group.metadata.name.clone(),
            about: group.metadata.about.clone(),
            member_count: group.members.len(),
            private: group.metadata.private,
            closed: group.metadata.closed,
            broadcast: group.metadata.is_broadcast,
        });
    }

    Ok(Json(result))
}

async fn handle_stats(
    State(state): State<Arc<ServerState>>,
    headers: HeaderMap,
) -> Result<impl IntoResponse, (StatusCode, Json<ErrorResponse>)> {
    let admin_state = get_admin_state(&state);
    if validate_session(&admin_state, &headers).is_none() {
        return Err(unauthorized());
    }

    let groups = &state.http_state.groups;
    let mut total_members = 0usize;
    let mut total_groups = 0usize;

    for entry in groups.iter() {
        total_groups += 1;
        total_members += entry.value().members.len();
    }

    Ok(Json(StatsResponse {
        active_connections: state.connection_counter.load(Ordering::Relaxed),
        total_groups,
        total_members,
        whitelisted_count: state.whitelist.len(),
        uptime_seconds: state.start_time.elapsed().as_secs(),
    }))
}

async fn handle_relay_info(
    State(state): State<Arc<ServerState>>,
) -> impl IntoResponse {
    let groups = &state.http_state.groups;
    let mut group_count = 0usize;

    for _ in groups.iter() {
        group_count += 1;
    }

    Json(RelayInfoResponse {
        name: "Obelisk Groups Relay".to_string(),
        description: "NIP-29 groups relay for Obelisk. Auth-required, whitelisted access."
            .to_string(),
        group_count,
        supported_nips: vec![1, 9, 11, 29, 40, 42, 70],
    })
}

// --- State helpers ---

fn get_admin_state(_state: &ServerState) -> AdminState {
    // AdminState is derived from ServerState on the fly.
    // Sessions and challenges are stored in the ServerState via lazy init.
    // For simplicity we store them in a once_cell inside this module.
    ADMIN_SHARED.get_or_init(|| AdminState {
        admin_pubkeys: vec![], // will be overridden
        sessions: Arc::new(RwLock::new(HashMap::new())),
        challenges: Arc::new(RwLock::new(HashMap::new())),
        relay_url: String::new(),
    });

    // We actually need per-server state. Use a global for now since there's one server.
    ADMIN_SHARED
        .get()
        .cloned()
        .unwrap()
}

use once_cell::sync::OnceCell;
static ADMIN_SHARED: OnceCell<AdminState> = OnceCell::new();

/// Initialize the admin state. Must be called once during server setup.
pub fn init_admin_state(admin_pubkeys: Vec<PublicKey>, relay_url: String) {
    let _ = ADMIN_SHARED.set(AdminState {
        admin_pubkeys,
        sessions: Arc::new(RwLock::new(HashMap::new())),
        challenges: Arc::new(RwLock::new(HashMap::new())),
        relay_url,
    });
}
