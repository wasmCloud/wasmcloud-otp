use crate::{Claims, ProviderArchiveResource};

use provider_archive::ProviderArchive;
use rustler::{Binary, Env, Error, ResourceArc};
use wascap::jwt::CapabilityProvider;

pub fn on_load(env: Env) -> bool {
    rustler::resource!(ProviderArchiveResource, env);
    true
}

pub(crate) fn extract_claims(par: &ProviderArchive) -> Result<Claims, Error> {
    println!("EXTRACTING CLAIMS");
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
