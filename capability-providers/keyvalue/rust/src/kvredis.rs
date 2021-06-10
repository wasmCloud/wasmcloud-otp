use log::info;
use std::collections::HashMap;
use std::error::Error;

const ENV_REDIS_URL: &str = "URL";

pub(crate) fn initialize_client(
    config: HashMap<String, String>,
) -> Result<redis::Client, Box<dyn Error + Sync + Send>> {
    let redis_url = match config.get(ENV_REDIS_URL) {
        Some(v) => v,
        None => "redis://0.0.0.0:6379/",
    }
    .to_string();

    info!("Attempting to connect to Redis at {}", redis_url);
    match redis::Client::open(redis_url.as_ref()) {
        Ok(c) => Ok(c),
        Err(e) => Err(format!("Failed to connect to redis: {}", e).into()),
    }
}
