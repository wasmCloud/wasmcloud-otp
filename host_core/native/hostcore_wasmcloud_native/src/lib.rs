#[macro_use]
extern crate rustler;

use futures::Future;
use lazy_static::lazy_static;
use nats::object_store::ObjectStore;
use nats::{Connection, JetStreamOptions};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::RwLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::task::JoinHandle;

use bindle::{filters::BindleFilter, provider::Provider};
use chrono::NaiveDateTime;
use nkeys::KeyPair;
use provider_archive::ProviderArchive;
use rustler::{Atom, Binary, Error};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_stream::StreamExt;
use wascap::prelude::*;

mod atoms;
mod client;
mod environment;
mod inv;
mod objstore;
mod oci;
mod par;
mod task;
mod wasmruntime;

lazy_static! {
    static ref CHUNKING_STORE: RwLock<Option<ObjectStore>> = RwLock::new(None);
}

// Static tokio runtime required for the NIF to interact with async Rust APIs
static TOKIO: Lazy<tokio::runtime::Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .build()
        .expect("Failed to start tokio runtime")
});

pub(crate) fn spawn<T>(task: T) -> JoinHandle<T::Output>
where
    T: Future + Send + 'static,
    T::Output: Send + 'static,
{
    TOKIO.spawn(task)
}

const CHONKY_THRESHOLD_BYTES: usize = 1024 * 700; // 700KB

pub(crate) const CORELABEL_ARCH: &str = "hostcore.arch";
pub(crate) const CORELABEL_OS: &str = "hostcore.os";
pub(crate) const CORELABEL_OSFAMILY: &str = "hostcore.osfamily";
const CLAIMS_NAME: &str = "claims.jwt";

#[derive(NifStruct)]
#[module = "HostCore.WasmCloud.Native.ProviderArchive"]
pub struct ProviderArchiveResource {
    claims: Claims,
    contract_id: String,
    vendor: String,
}

#[derive(NifStruct, Default)]
#[module = "HostCore.WasmCloud.Native.Claims"]
pub struct Claims {
    public_key: String,
    issuer: String,
    name: Option<String>,
    call_alias: Option<String>,
    version: Option<String>,
    revision: Option<i32>,
    tags: Option<Vec<String>>,
    caps: Option<Vec<String>>,
    expires_human: String,
    not_before_human: String,
}

impl From<wascap::jwt::Claims<wascap::jwt::CapabilityProvider>> for crate::Claims {
    fn from(c: wascap::jwt::Claims<wascap::jwt::CapabilityProvider>) -> Self {
        provider_claims_to_crate_claims(c)
    }
}

impl From<wascap::jwt::Claims<wascap::jwt::Actor>> for crate::Claims {
    fn from(c: wascap::jwt::Claims<wascap::jwt::Actor>) -> Self {
        actor_claims_to_crate_claims(c)
    }
}

pub(crate) fn actor_claims_to_crate_claims(c: wascap::jwt::Claims<wascap::jwt::Actor>) -> Claims {
    let metadata = c.metadata.unwrap_or_default();
    let revision = revision_or_iat(metadata.rev, c.issued_at);
    Claims {
        issuer: c.issuer,
        public_key: c.subject,
        revision,
        tags: None,
        version: metadata.ver,
        caps: metadata.caps,
        name: metadata.name,
        expires_human: stamp_to_human(c.expires).unwrap_or_else(|| "never".to_string()),
        not_before_human: stamp_to_human(c.not_before).unwrap_or_else(|| "immediately".to_string()),
        ..Default::default()
    }
}

pub(crate) fn provider_claims_to_crate_claims(
    c: wascap::jwt::Claims<wascap::jwt::CapabilityProvider>,
) -> Claims {
    let metadata = c.metadata.unwrap_or_default();
    let revision = revision_or_iat(metadata.rev, c.issued_at);
    Claims {
        issuer: c.issuer,
        public_key: c.subject,
        revision,
        tags: None,
        version: metadata.ver,
        name: metadata.name,
        expires_human: stamp_to_human(c.expires).unwrap_or_else(|| "never".to_string()),
        not_before_human: stamp_to_human(c.not_before).unwrap_or_else(|| "immediately".to_string()),
        ..Default::default()
    }
}

#[derive(NifUnitEnum)]
pub enum TargetType {
    Actor,
    Provider,
}

#[derive(Debug, Copy, Clone, NifUnitEnum)]
pub enum KeyType {
    Server,
    Cluster,
    Operator,
    Account,
    User,
    Module,
    Provider,
}

rustler::init!(
    "Elixir.HostCore.WasmCloud.Native",
    [
        set_chunking_connection_config,
        dechunk_inv,
        chunk_inv,
        extract_claims,
        generate_key,
        generate_invocation_bytes,
        validate_antiforgery,
        get_oci_path,
        get_oci_bytes,
        par_from_path,
        par_cache_path,
        detect_core_host_labels,
        pk_from_seed,
        get_provider_bindle,
        get_actor_bindle,
        wasmruntime::new,
        wasmruntime::version,
        wasmruntime::start_actor,
        wasmruntime::call_actor,
        wasmruntime::receive_callback_result
    ],
    load = load
);

/// Create and store the NATS connection to be used for chunking
/// invocations
#[rustler::nif]
fn set_chunking_connection_config(config: HashMap<String, String>) -> Result<Atom, Error> {
    let nc = get_nats_connection(&config)?;
    // TODO: add JS domain
    let jsoptions = if let Some(d) = config.get("js_domain").cloned() {
        JetStreamOptions::new().domain(&d)
    } else {
        JetStreamOptions::new()
    };
    let js = nats::jetstream::JetStream::new(nc, jsoptions);
    let lattice = config
        .get("lattice")
        .cloned()
        .unwrap_or_else(|| "default".to_string());
    let store = objstore::create_or_reuse_store(&js, &lattice).map_err(to_rustler_err)?;

    *CHUNKING_STORE.write().unwrap() = Some(store);

    Ok(atoms::ok())
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_provider_bindle(
    creds_override: Option<HashMap<String, String>>,
    bindle_id: String,
    link_name: String,
) -> Result<(Atom, ProviderArchiveResource), Error> {
    task::TOKIO.block_on(async {
        let bindle_client = client::get_client(creds_override, &bindle_id)
            .await
            .map_err(to_rustler_err)?;
        let bindle_id = crate::client::normalize_bindle_id(&bindle_id);
        // Get the invoice first
        let inv = bindle_client.get_invoice(bindle_id).await.map_err(|e| {
            println!("{:?}", e);
            to_rustler_err(e)
        })?;
        // Now filter to figure out which parcels to get (should only get the claims and the provider based on arch)
        let mut filter = BindleFilter::new(&inv);
        filter
            .activate_feature("wasmcloud", "arch", std::env::consts::ARCH)
            .activate_feature("wasmcloud", "os", std::env::consts::OS);
        let filtered = filter.filter();
        if filtered.len() != 2 {
            return Err(to_rustler_err(
                "Found more than a single provider, this is likely a problem with your bindle",
            ));
        }

        let (claims_parcel, provider_parcel) = {
            let (mut c, mut p) = filtered
                .into_iter()
                .partition::<Vec<bindle::Parcel>, _>(|p| p.label.name == CLAIMS_NAME);
            if c.len() != 1 {
                return Err(to_rustler_err("No claims were found in parcel"));
            }
            if p.len() != 1 {
                return Err(to_rustler_err(
                    "No providers (or multiple) were found in parcel",
                ));
            }
            // Safety: Can unwrap because of checked length
            (c.pop().unwrap(), p.pop().unwrap())
        };

        let claims: wascap::jwt::Claims<wascap::jwt::CapabilityProvider> = {
            let mut stream = bindle_client
                .get_parcel(&inv.bindle.id, &claims_parcel.label.sha256)
                .await
                .expect("Unable to get parcel");
            let mut data = Vec::new();
            while let Some(res) = stream.next().await {
                let bytes = res.map_err(to_rustler_err)?;
                data.extend(bytes);
            }
            wascap::jwt::Claims::decode(
                std::str::from_utf8(&data)
                    .map_err(|_| to_rustler_err("Invalid UTF-8 data found in claims"))?,
            )
            .map_err(to_rustler_err)?
        };

        let contract_id = claims
            .metadata
            .as_ref()
            .map(|m| m.capid.clone())
            .unwrap_or_default();

        let vendor = claims
            .metadata
            .as_ref()
            .map(|m| m.vendor.clone())
            .unwrap_or_default();

        let claims: Claims = claims.into();

        // Now get the parcel (if it doesn't already exist on disk)
        if let Some(mut file) = get_provider_file(&par::cache_path(
            &claims.public_key,
            claims.revision.unwrap_or_default(),
            &contract_id,
            &link_name,
        )?)
        .await?
        {
            let mut written = 0usize;
            let mut stream = bindle_client
                .get_parcel(&inv.bindle.id, &provider_parcel.label.sha256)
                .await
                .expect("Unable to get parcel");
            while let Some(res) = stream.next().await {
                let bytes = res.map_err(to_rustler_err)?;
                written += bytes.len();
                file.write_all(&bytes).await.map_err(to_rustler_err)?;
            }
            file.flush().await.map_err(to_rustler_err)?;
            if written == 0 {
                return Err(to_rustler_err("No provider parcel found (or was empty)"));
            }
        }

        Ok((
            atoms::ok(),
            ProviderArchiveResource {
                claims,
                contract_id,
                vendor,
            },
        ))
    })
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_actor_bindle(
    creds_override: Option<HashMap<String, String>>,
    bindle_id: String,
) -> Result<(Atom, Vec<u8>), Error> {
    task::TOKIO.block_on(async {
        // Get the invoice, validate this bindle contains an actor, fetch the actor and return
        let bindle_client = client::get_client(creds_override, &bindle_id)
            .await
            .map_err(to_rustler_err)?;
        let bindle_id = crate::client::normalize_bindle_id(&bindle_id);
        let inv = bindle_client
            .get_invoice(bindle_id)
            .await
            .map_err(to_rustler_err)?;

        // TODO: We may want to allow more than one down the line, or include the JWT separately as
        // part of the bindle. For now we just expect the single parcel
        let parcels = inv.parcel.unwrap();
        if parcels.len() != 1 {
            return Err(to_rustler_err(
                "Actor bindle should only contain a single parcel",
            ));
        }

        // SAFETY: We validated a length of 1 just above
        let mut stream = bindle_client
            .get_parcel(&inv.bindle.id, &parcels[0].label.sha256)
            .await
            .expect("Unable to get parcel");
        let mut data = Vec::new();
        while let Some(res) = stream.next().await {
            let bytes = res.map_err(to_rustler_err)?;
            data.extend(bytes);
        }
        Ok((atoms::ok(), data))
    })
}

fn to_rustler_err(e: impl std::fmt::Debug) -> Error {
    // NOTE: Debug is better here otherwise the nested errors don't get printed
    Error::Term(Box::new(format!("{:?}", e)))
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_oci_bytes(
    creds_override: Option<HashMap<String, String>>,
    oci_ref: String,
    allow_latest: bool,
    allowed_insecure: Vec<String>,
) -> Result<(Atom, Vec<u8>), Error> {
    task::TOKIO.block_on(async {
        let path =
            match oci::fetch_oci_path(&oci_ref, allow_latest, allowed_insecure, creds_override)
                .await
            {
                Ok(p) => p,
                Err(e) => return Err(rustler::Error::Term(Box::new(format!("{}", e)))),
            };
        let mut output = Vec::new();
        let mut file = tokio::fs::File::open(path).await.map_err(to_rustler_err)?;
        file.read_to_end(&mut output)
            .await
            .map_err(to_rustler_err)?;
        Ok((atoms::ok(), output))
    })
}

#[rustler::nif(schedule = "DirtyIo")]
fn get_oci_path(
    creds_override: Option<HashMap<String, String>>,
    oci_ref: String,
    allow_latest: bool,
    allowed_insecure: Vec<String>,
) -> Result<(Atom, String), Error> {
    task::TOKIO.block_on(async {
        match oci::fetch_oci_path(&oci_ref, allow_latest, allowed_insecure, creds_override).await {
            Ok(p) => Ok((
                atoms::ok(),
                p.to_str().map(|s| s.to_owned()).unwrap_or_default(),
            )),
            Err(e) => Err(rustler::Error::Term(Box::new(format!("{}", e)))),
        }
    })
}

#[rustler::nif]
fn pk_from_seed(seed: String) -> Result<(Atom, String), Error> {
    let key = KeyPair::from_seed(&seed).map_err(|e| {
        rustler::Error::Term(Box::new(format!(
            "Failed to determine public key from seed: {}",
            e
        )))
    })?;

    Ok((atoms::ok(), key.public_key()))
}

#[rustler::nif]
fn par_from_path(
    path: String,
    link_name: String,
) -> Result<(Atom, ProviderArchiveResource), Error> {
    task::TOKIO.block_on(async {
        match ProviderArchive::try_load_target_from_file(path, &par::native_target()).await {
            Ok(par) => {
                let claims = par::extract_claims(&par)?;
                let contract_id = par::get_capid(&par)?;

                // Only write the file if it doesn't exist
                if let Some(mut file) = get_provider_file(&par::cache_path(
                    &claims.public_key,
                    claims.revision.unwrap_or_default(),
                    &contract_id,
                    &link_name,
                )?)
                .await?
                {
                    file.write_all(&par::extract_target_bytes(&par)?)
                        .await
                        .map_err(to_rustler_err)?;
                    file.flush().await.map_err(to_rustler_err)?;
                }
                Ok((
                    atoms::ok(),
                    ProviderArchiveResource {
                        claims,
                        contract_id,
                        vendor: par::get_vendor(&par)?,
                    },
                ))
            }
            Err(e) => Err(Error::Term(Box::new(format!("{}", e)))),
        }
    })
}

#[rustler::nif]
fn par_cache_path(
    subject: String,
    rev: i32,
    contract_id: String,
    link_name: String,
) -> Result<String, Error> {
    par::cache_path(&subject, rev, &contract_id, &link_name)
}

/// Extracts the claims from the raw bytes of a _signed_ WebAssembly module/actor and returns them
/// in the form of a simple struct that will bubble its way up to Elixir as a native struct
#[rustler::nif]
fn extract_claims(binary: Binary) -> Result<(Atom, Claims), Error> {
    let bytes = binary.as_slice();

    let extracted = match wasm::extract_claims(&bytes) {
        Ok(Some(c)) => c,
        Ok(None) => {
            return Err(rustler::Error::Term(Box::new(
                "No claims found in source module",
            )));
        }
        Err(e) => {
            return Err(rustler::Error::Term(Box::new(format!(
                "Failed to extract claims from module: {}",
                e
            ))));
        }
    };
    let c: wascap::jwt::Claims<wascap::jwt::Actor> = extracted.claims;
    let m: wascap::jwt::Actor = c.metadata.unwrap();
    let v = validate_token::<wascap::jwt::Actor>(&extracted.jwt);
    match &v {
        Ok(v) => {
            if v.expired {
                return Err(rustler::Error::Term(Box::new("Claims token expired")));
            } else if v.cannot_use_yet {
                return Err(rustler::Error::Term(Box::new(
                    "Claims token cannot be used yet",
                )));
            } else if !v.signature_valid {
                return Err(rustler::Error::Term(Box::new(
                    "Invalid signature on module token",
                )));
            }
        }
        Err(e) => {
            return Err(rustler::Error::Term(Box::new(format!(
                "Failed to validate claims token: {}",
                e
            ))));
        }
    }
    let v = v.unwrap();

    let revision = revision_or_iat(m.rev, c.issued_at);

    let out = Claims {
        caps: m.caps,
        public_key: c.subject,
        issuer: c.issuer,
        name: m.name,
        call_alias: m.call_alias,
        version: m.ver,
        revision,
        tags: m.tags,
        expires_human: v.expires_human,
        not_before_human: v.not_before_human,
    };

    Ok((atoms::ok(), out))
}

#[rustler::nif]
fn generate_key(key_type: KeyType) -> Result<(String, String), Error> {
    let kp = match key_type {
        KeyType::Server => KeyPair::new_server(),
        KeyType::Cluster => KeyPair::new_cluster(),
        KeyType::Operator => KeyPair::new_operator(),
        KeyType::Account => KeyPair::new_account(),
        KeyType::User => KeyPair::new_user(),
        KeyType::Module => KeyPair::new_module(),
        KeyType::Provider => KeyPair::new_service(),
    };
    let seed = kp.seed().unwrap();
    let pk = kp.public_key();

    Ok((pk, seed))
}

#[rustler::nif(schedule = "DirtyIo")]
fn dechunk_inv(inv_id: String) -> Result<(Atom, Vec<u8>), Error> {
    Ok((atoms::ok(), objstore::unchonk_from_object_store(&inv_id)?))
}

#[rustler::nif(schedule = "DirtyIo")]
fn chunk_inv(inv_id: String, data: Binary) -> Result<Atom, Error> {
    objstore::chonk_to_object_store(&inv_id, &mut data.as_slice())?;

    Ok(atoms::ok())
}

#[allow(clippy::too_many_arguments)]
#[rustler::nif(schedule = "DirtyIo")]
fn generate_invocation_bytes(
    host_seed: String,
    origin: String, // always comes from actor
    target_type: TargetType,
    target_key: String,
    target_contract_id: String,
    target_link_name: String,
    operation: String,
    msg: Binary,
) -> Result<Vec<u8>, Error> {
    let mut inv = inv::Invocation::new(
        &KeyPair::from_seed(&host_seed).unwrap(),
        inv::WasmCloudEntity::actor(&origin),
        if let TargetType::Actor = target_type {
            inv::WasmCloudEntity::actor(&target_key)
        } else {
            inv::WasmCloudEntity::capability(&target_key, &target_contract_id, &target_link_name)
        },
        &operation,
        msg.as_slice().to_vec(),
    );
    if msg.len() > CHONKY_THRESHOLD_BYTES {
        inv.msg = vec![];
        objstore::chonk_to_object_store(&inv.id, &mut msg.as_slice())?;
    }
    Ok(inv::serialize(&inv).unwrap())
}

#[rustler::nif]
fn validate_antiforgery(inv: Binary, valid_issuers: Vec<String>) -> Result<Atom, Error> {
    inv::deserialize::<inv::Invocation>(inv.as_slice())
        .map_err(|_e| rustler::Error::Term(Box::new("Failed to deserialize invocation")))
        .and_then(|i| {
            i.validate_antiforgery(valid_issuers)
                .map_err(|e| rustler::Error::Term(Box::new(format!("{}", e))))
        })
}

#[rustler::nif]
fn detect_core_host_labels() -> HashMap<String, String> {
    let mut hm = HashMap::new();
    hm.insert(
        CORELABEL_ARCH.to_string(),
        std::env::consts::ARCH.to_string(),
    );
    hm.insert(CORELABEL_OS.to_string(), std::env::consts::OS.to_string());
    hm.insert(
        CORELABEL_OSFAMILY.to_string(),
        std::env::consts::FAMILY.to_string(),
    );
    hm
}

async fn get_provider_file(path: &str) -> Result<Option<tokio::fs::File>, Error> {
    let p = PathBuf::from(path);
    // Check if the file exists and return
    if tokio::fs::metadata(&p).await.is_ok() {
        return Ok(None);
    }
    tokio::fs::create_dir_all(p.parent().ok_or(Error::BadArg)?)
        .await
        .map_err(to_rustler_err)?;

    let mut open_opts = tokio::fs::OpenOptions::new();
    open_opts.create(true).truncate(true).write(true);
    #[cfg(target_family = "unix")]
    open_opts.mode(0o755);
    open_opts.open(p).await.map_err(to_rustler_err).map(Some)
}

fn load(env: rustler::Env, _: rustler::Term) -> bool {
    par::on_load(env);
    wasmruntime::on_load(env);
    environment::on_load(env);

    true
}

// Inspects revision, if missing or zero then replace with iat value
pub(crate) fn revision_or_iat(rev: Option<i32>, iat: u64) -> Option<i32> {
    if rev.is_some() && rev.unwrap() > 0 {
        rev
    } else {
        Some(iat as i32)
    }
}

pub(crate) fn stamp_to_human(stamp: Option<u64>) -> Option<String> {
    stamp.map(|s| {
        let now = NaiveDateTime::from_timestamp_opt(since_the_epoch().as_secs() as i64, 0)
            .unwrap_or_default();
        let then = NaiveDateTime::from_timestamp_opt(s as i64, 0).unwrap_or_default();

        let diff = then - now;

        let ht = chrono_humanize::HumanTime::from(diff);
        format!("{}", ht)
    })
}

fn since_the_epoch() -> Duration {
    let start = SystemTime::now();
    start
        .duration_since(UNIX_EPOCH)
        .expect("A timey wimey problem has occurred!")
}

fn get_nats_connection(config: &HashMap<String, String>) -> Result<Connection, Error> {
    let host = config
        .get("host")
        .cloned()
        .unwrap_or_else(|| "127.0.0.1".to_string());
    let port = config
        .get("port")
        .cloned()
        .unwrap_or_else(|| "4222".to_string());
    let nats_url = format!("{}:{}", host, port);

    let nc = match (config.get("jwt").cloned(), config.get("seed").cloned()) {
        (Some(jwt), Some(seed)) if !jwt.is_empty() && !seed.is_empty() => {
            let kp = KeyPair::from_seed(&seed).map_err(to_rustler_err)?;
            nats::Options::with_jwt(
                move || Ok(jwt.clone()),
                move |nonce| kp.sign(nonce).unwrap(),
            )
            .connect(&nats_url)
        }
        _ => nats::connect(&nats_url),
    }
    .map_err(to_rustler_err)?;

    Ok(nc)
}
