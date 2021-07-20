#[macro_use]
extern crate rustler;

use nkeys::KeyPair;
use provider_archive::ProviderArchive;
use rustler::{Atom, Binary, Error, ResourceArc};
use std::collections::HashMap;
use wascap::prelude::*;

mod atoms;
mod inv;
mod oci;
mod par;
mod task;

pub(crate) const CORELABEL_ARCH: &str = "hostcore.arch";
pub(crate) const CORELABEL_OS: &str = "hostcore.os";
pub(crate) const CORELABEL_OSFAMILY: &str = "hostcore.osfamily";

#[derive(NifStruct)]
#[module = "HostCore.WasmCloud.Native.ProviderArchive"]
pub struct ProviderArchiveResource {
    claims: Claims,
    target_bytes: Vec<u8>,
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
        extract_claims,
        generate_key,
        generate_invocation_bytes,
        validate_antiforgery,
        get_oci_bytes,
        par_from_bytes,
        par_cache_path,
        detect_core_host_labels,
    ],
    load = load
);

#[rustler::nif(schedule = "DirtyIo")]
fn get_oci_bytes(
    oci_ref: String,
    allow_latest: bool,
    allowed_insecure: Vec<String>,
) -> Result<Vec<u8>, Error> {
    task::TOKIO
        .block_on(async { oci::fetch_oci_bytes(&oci_ref, allow_latest, allowed_insecure).await })
        .map_err(|_e| rustler::Error::Term(Box::new("Failed to fetch OCI bytes")))
}

#[rustler::nif]
fn par_from_bytes(binary: Binary) -> Result<ProviderArchiveResource, Error> {
    match ProviderArchive::try_load(binary.as_slice()) {
        Ok(par) => {
            return Ok(ProviderArchiveResource {
                claims: par::extract_claims(&par)?,
                target_bytes: par::extract_target_bytes(&par)?,
                contract_id: par::get_capid(&par)?,
                vendor: par::get_vendor(&par)?,
            })
        }
        Err(_) => Err(Error::BadArg),
    }
}

#[rustler::nif]
fn par_cache_path(subject: String, rev: u32) -> Result<String, Error> {
    par::cache_path(subject, rev)
}
/// Extracts the claims from the raw bytes of a _signed_ WebAssembly module/actor and returns them
/// in the form of a simple struct that will bubble its way up to Elixir as a native struct
#[rustler::nif]
fn extract_claims(binary: Binary) -> Result<Claims, Error> {
    let bytes = binary.as_slice();

    let extracted = match wasm::extract_claims(&bytes) {
        Ok(Some(c)) => c,
        Ok(None) => {
            return Err(rustler::Error::Atom("No claims found in source module"));
        }
        Err(_e) => {
            return Err(rustler::Error::Atom("Failed to extract claims from module"));
        }
    };
    let c: wascap::jwt::Claims<wascap::jwt::Actor> = extracted.claims;
    let m: wascap::jwt::Actor = c.metadata.unwrap();
    match validate_token::<wascap::jwt::Actor>(&extracted.jwt) {
        Ok(v) => {
            if v.expired {
                return Err(rustler::Error::Atom("Claims token expired"));
            } else if v.cannot_use_yet {
                return Err(rustler::Error::Atom("Claims token cannot be used yet"));
            } else if !v.signature_valid {
                return Err(rustler::Error::Atom("Invalid signature on module token"));
            }
        }
        Err(_e) => {
            return Err(rustler::Error::Atom("Failed to validate claims token"));
        }
    }

    let out = Claims {
        caps: m.caps,
        public_key: c.subject,
        issuer: c.issuer,
        name: m.name,
        call_alias: m.call_alias,
        version: m.ver,
        revision: m.rev,
        tags: m.tags,
    };

    Ok(out)
}

#[rustler::nif]
fn generate_key<'a>(key_type: KeyType) -> Result<(String, String), Error> {
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

#[rustler::nif]
fn generate_invocation_bytes<'a>(
    host_seed: String,
    origin: String, // always comes from actor
    target_type: TargetType,
    target_key: String,
    target_contract_id: String,
    target_link_name: String,
    operation: String,
    msg: Binary,
) -> Result<Vec<u8>, Error> {
    let inv = inv::Invocation::new(
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
    Ok(inv::serialize(&inv).unwrap())
}

#[rustler::nif]
fn validate_antiforgery<'a>(inv: Binary, valid_issuers: Vec<String>) -> Result<(), Error> {
    inv::deserialize::<inv::Invocation>(inv.as_slice())
        .map_err(|_e| rustler::Error::Term(Box::new("Failed to deserialize invocation")))
        .and_then(|i| {
            i.validate_antiforgery(valid_issuers).map_err(|e| {
                rustler::Error::Term(Box::new(format!(
                    "Validation of invocation/AF token failed: {}",
                    e
                )))
            })
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

fn load(env: rustler::Env, _: rustler::Term) -> bool {
    par::on_load(env);
    true
}
