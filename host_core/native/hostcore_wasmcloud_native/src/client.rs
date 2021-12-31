use std::env::var;

use bindle::{
    cache::DumbCache,
    client::{
        tokens::{HttpBasic, LongLivedToken, NoToken, TokenManager},
        Client, Result as BindleResult,
    },
    provider::file::FileProvider,
    search::NoopEngine,
};

const BINDLE_USER_NAME_ENV: &str = "BINDLE_USER_NAME";
const BINDLE_TOKEN_ENV: &str = "BINDLE_TOKEN";
const BINDLE_PASSWORD_ENV: &str = "BINDLE_PASSWORD";
const BINDLE_URL_ENV: &str = "BINDLE_URL";

const DEFAULT_BINDLE_URL: &str = "http://localhost:8080/v1/";
const CACHE_DIR: &str = "wasmcloud_bindlecache";

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

/// Returns a bindle client configured to cache to disk
pub async fn get_client() -> Result<CachedClient, Box<dyn std::error::Error + Sync + Send>> {
    let auth = if let Ok(pw) = var(BINDLE_PASSWORD_ENV) {
        if let Ok(username) = var(BINDLE_USER_NAME_ENV) {
            PickYourAuth::Http(HttpBasic::new(&username, &pw))
        } else {
            return Err(
                "Bindle password was set, but no username was given. Unable to configure client"
                    .into(),
            );
        }
    } else if let Ok(token) = var(BINDLE_TOKEN_ENV) {
        PickYourAuth::LongLived(LongLivedToken::new(&token))
    } else {
        PickYourAuth::None(NoToken)
    };

    // Make sure the cache dir exists
    let bindle_dir = std::env::temp_dir().join(CACHE_DIR);
    tokio::fs::create_dir_all(&bindle_dir).await?;
    let client = Client::new(
        &var(BINDLE_URL_ENV).unwrap_or_else(|_| DEFAULT_BINDLE_URL.to_owned()),
        auth,
    )?;
    let local = FileProvider::new(bindle_dir, NoopEngine::default()).await;
    Ok(DumbCache::new(client, local))
}
