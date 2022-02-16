use crate::{Claims, ProviderArchiveResource};

use provider_archive::ProviderArchive;
use rustler::{Env, Error};
use std::env::temp_dir;

pub fn on_load(env: Env) -> bool {
    rustler::resource!(ProviderArchiveResource, env);
    true
}

pub(crate) fn get_capid(par: &ProviderArchive) -> Result<String, Error> {
    match par.claims() {
        Some(c) => Ok(c.metadata.unwrap_or_default().capid),
        None => Err(Error::Term(Box::new("No claims found in provider archive"))),
    }
}

pub(crate) fn get_vendor(par: &ProviderArchive) -> Result<String, Error> {
    match par.claims() {
        Some(c) => Ok(c.metadata.unwrap_or_default().vendor),
        None => Err(Error::Term(Box::new("No claims found in provider archive"))),
    }
}

pub(crate) fn extract_claims(par: &ProviderArchive) -> Result<Claims, Error> {
    par.claims()
        .map(Claims::from)
        .ok_or_else(|| Error::Term(Box::new("No claims found in provider archive")))
}

pub(crate) fn extract_target_bytes(par: &ProviderArchive) -> Result<Vec<u8>, Error> {
    let target = native_target();
    match par.target_bytes(&target) {
        Some(b) => Ok(b),
        None => Err(Error::Term(Box::new(
            "No suitable target found in provider archive",
        ))),
    }
}

pub(crate) fn cache_path(
    subject: String,
    rev: u32,
    contract_id: String,
    link_name: String,
) -> Result<String, Error> {
    let mut path = temp_dir();
    path.push("wasmcloudcache");
    path.push(&subject);
    path.push(format!("{}", rev));

    let contract = normalize_for_filename(&contract_id);
    let link_name = normalize_for_filename(&link_name);
    let filename = if cfg!(windows) {
        format!("{}_{}.exe", contract, link_name)
    } else {
        format!("{}_{}", contract, link_name)
    };
    path.push(filename);

    match path.into_os_string().into_string() {
        Ok(s) => Ok(s),
        Err(_e) => Err(Error::Term(Box::new(
            "FATAL - Could not convert path into string",
        ))),
    }
}

fn normalize_for_filename(input: &str) -> String {
    input
        .to_lowercase()
        .replace(|c: char| !c.is_ascii_alphanumeric(), "_")
}

pub(crate) fn native_target() -> String {
    format!("{}-{}", std::env::consts::ARCH, std::env::consts::OS)
}
