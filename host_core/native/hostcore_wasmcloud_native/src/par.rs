use std::sync::RwLock;

use crate::ProviderArchiveResource;
use provider_archive::ProviderArchive;
use rustler::{Binary, Env, ResourceArc};

pub fn on_load(env: Env) -> bool {
    rustler::resource!(ProviderArchiveResource, env);
    true
}

pub fn from_bytes(bytes: Binary) -> ResourceArc<ProviderArchiveResource> {
    ResourceArc::new(ProviderArchiveResource {
        inner: RwLock::new(ProviderArchive::try_load(bytes.as_slice()).unwrap()),
    })
}
