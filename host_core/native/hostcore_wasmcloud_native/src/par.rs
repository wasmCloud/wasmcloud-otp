use crate::{Claims, ProviderArchiveResource};

use provider_archive::ProviderArchive;
use rustler::{Binary, Env, Error, ResourceArc};
use wascap::jwt::CapabilityProvider;

pub fn on_load(env: Env) -> bool {
    rustler::resource!(ProviderArchiveResource, env);
    true
}

pub(crate) fn get_capid(par: &ProviderArchive) -> Result<String, Error> {
    match par.claims() {
        Some(c) => {
            Ok(c.metadata.unwrap_or_default().capid)
        },
        None => Err(Error::Atom("No claims found in provider archive"))
    }
}

pub(crate) fn get_vendor(par: &ProviderArchive) -> Result<String, Error> {
    match par.claims() {
        Some(c) => {
            Ok(c.metadata.unwrap_or_default().vendor)
        },
        None => Err(Error::Atom("No claims found in provider archive"))
    }
}

pub(crate) fn extract_claims(par: &ProviderArchive) -> Result<Claims, Error> {    
    match par.claims() {
        Some(c) => Ok(crate::Claims {
            issuer: c.issuer,
            public_key: c.subject,
            revision: c
                .metadata
                .clone()
                .unwrap_or(CapabilityProvider::default())
                .rev,
            tags: None,
            version: c.metadata.unwrap_or(CapabilityProvider::default()).ver,
            ..Default::default()
        }),
        None => Err(Error::Atom("No claims found in provider archive")),
    }
}

pub(crate) fn extract_target_bytes(par: &ProviderArchive) -> Result<Vec<u8>, Error> {
    let target = native_target();
    match par.target_bytes(&target) {
        Some(b) => Ok(b),
        None => Err(Error::Atom("No suitable target found in provider archive"))
    }
}

fn native_target() -> String {
    format!("{}-{}", std::env::consts::ARCH, std::env::consts::OS)
}
