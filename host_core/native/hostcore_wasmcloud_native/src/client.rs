use std::{collections::HashMap, env::var, path::PathBuf};

use bindle::{
    cache::DumbCache,
    client::{
        tokens::{HttpBasic, LongLivedToken, NoToken, TokenManager},
        Client, ClientBuilder, Result as BindleResult,
    },
    provider::file::FileProvider,
    search::NoopEngine,
    signature::{KeyRing, KeyRingLoader, KeyRingSaver},
    SignatureRole, VerificationStrategy,
};

const BINDLE_USER_NAME_ENV: &str = "BINDLE_USER_NAME";
const BINDLE_TOKEN_ENV: &str = "BINDLE_TOKEN";
const BINDLE_PASSWORD_ENV: &str = "BINDLE_PASSWORD";
const BINDLE_URL_ENV: &str = "BINDLE_URL";
const BINDLE_KEYRING_PATH: &str = "BINDLE_KEYRING_PATH";

const DEFAULT_BINDLE_URL: &str = "http://localhost:8080/v1/";
const CACHE_DIR: &str = "wasmcloud_bindlecache";
const KEYRING_FILE: &str = "keyring.toml";

pub type CachedClient = DumbCache<FileProvider<NoopEngine>, Client<PickYourAuth>>;

/// Trying to do a dynamically configured auth leads to big if/else blocks to get a client. This
/// works around it
#[derive(Clone)]
pub enum PickYourAuth {
    None(NoToken),
    Http(HttpBasic),
    LongLived(LongLivedToken),
}

#[async_trait::async_trait]
impl TokenManager for PickYourAuth {
    async fn apply_auth_header(
        &self,
        builder: reqwest::RequestBuilder,
    ) -> BindleResult<reqwest::RequestBuilder> {
        match &self {
            PickYourAuth::None(nt) => nt.apply_auth_header(builder).await,
            PickYourAuth::Http(h) => h.apply_auth_header(builder).await,
            PickYourAuth::LongLived(l) => l.apply_auth_header(builder).await,
        }
    }
}

fn get_bindle_auth(creds_override: Option<HashMap<String, String>>) -> PickYourAuth {
    if let Some(co) = creds_override {
        match (co.get("username"), co.get("password"), co.get("token")) {
            (Some(u), Some(p), _) => PickYourAuth::Http(HttpBasic::new(u, p)),
            (_, _, Some(t)) => PickYourAuth::LongLived(LongLivedToken::new(t)),
            _ => PickYourAuth::None(NoToken),
        }
    } else {
        match (
            var(BINDLE_PASSWORD_ENV),
            var(BINDLE_USER_NAME_ENV),
            var(BINDLE_TOKEN_ENV),
        ) {
            (Ok(pw), Ok(username), _) => PickYourAuth::Http(HttpBasic::new(&username, &pw)),
            (_, _, Ok(token)) => PickYourAuth::LongLived(LongLivedToken::new(&token)),
            _ => {
                // used to return an error here. Instead, default to anonymous and hope
                // for the best. If insufficient creds were provided, the fetch call will
                // fail anyway
                PickYourAuth::None(NoToken)
            }
        }
    }
}

/// Returns a bindle client configured to cache to disk
pub async fn get_client(
    creds_override: Option<HashMap<String, String>>,
    bindle_id: &str,
) -> Result<CachedClient, Box<dyn std::error::Error + Sync + Send>> {
    let auth = get_bindle_auth(creds_override.clone());

    // Make sure the cache dir exists
    let temp_dir = std::env::temp_dir();
    let bindle_dir = temp_dir.join(CACHE_DIR);

    let keyring_path = if let Ok(bindle_keyring_path) = var(BINDLE_KEYRING_PATH) {
        PathBuf::from(bindle_keyring_path)
    } else {
        bindle_dir.join(KEYRING_FILE)
    };
    tokio::fs::create_dir_all(&bindle_dir).await?;
    let bindle_url = if creds_override.is_some() {
        extract_server(bindle_id)
    } else {
        var(BINDLE_URL_ENV).unwrap_or_else(|_| DEFAULT_BINDLE_URL.to_owned())
    };
    let keyring: KeyRing = match keyring_path.load().await {
        Ok(k) => k,
        Err(e) => {
            eprintln!("WARN: Got error when trying to load keyring: {}\n\n Attempting to fetch host keys from server", e);
            let client = Client::new(
                &bindle_url,
                auth.clone(),
                std::sync::Arc::new(KeyRing::default()),
            )?;

            let k = client.get_host_keys().await.map_err(|e| {
                format!(
                    "Unable to fetch host keys for validation and no keyring was provided: {}",
                    e
                )
            })?;
            if let Err(e) = keyring_path.save(&k).await {
                eprintln!("WARN: Unable to save fetched host keys to {}. Will continue with keyring in memory: {}", keyring_path.display(), e);
            }
            k
        }
    };
    let client = ClientBuilder::default()
        .verification_strategy(VerificationStrategy::MultipleAttestation(vec![
            SignatureRole::Host,
        ]))
        .build(&bindle_url, auth, std::sync::Arc::new(keyring))?;
    let local = FileProvider::new(bindle_dir, NoopEngine::default()).await;
    Ok(DumbCache::new(client, local))
}

// By the time the bindle ID gets here, if it's in "secure registry" form (invoice@server)
fn extract_server(bindle_id: &str) -> String {
    let parts: Vec<_> = bindle_id.split('@').collect();
    if parts.len() == 2 {
        parts[1].to_owned()
    } else {
        var(BINDLE_URL_ENV).unwrap_or_else(|_| DEFAULT_BINDLE_URL.to_owned())
    }
}

// If the bindle ID is in "secure registry" form, just take the invoice portion of invoice@server
pub(crate) fn normalize_bindle_id(bindle_id: &str) -> String {
    let parts: Vec<_> = bindle_id.split('@').collect();
    if parts.len() == 2 {
        parts[0].to_owned()
    } else {
        bindle_id.to_owned()
    }
}
