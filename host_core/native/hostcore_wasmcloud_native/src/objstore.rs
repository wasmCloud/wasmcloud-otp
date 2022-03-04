use std::io::Read;

use nats::{
    jetstream::JetStream,
    object_store::{Config, ObjectStore},
};
use rustler::Error;

use crate::to_rustler_err;

pub(crate) fn chonk_to_object_store(id: &str, bytes: &mut impl Read) -> Result<(), Error> {
    let store = crate::CHUNKING_STORE.read().unwrap();
    if let Some(ref store) = *store {
        let _ = store.put(id, bytes).map_err(to_rustler_err)?;
    }

    Ok(())
}

pub(crate) fn unchonk_from_object_store(id: &str) -> Result<Vec<u8>, Error> {
    let mut result = Vec::new();
    let store = crate::CHUNKING_STORE.read().unwrap();
    if let Some(ref store) = *store {
        store
            .get(id)
            .map_err(to_rustler_err)?
            .read_to_end(&mut result)
            .map_err(to_rustler_err)?;
        let _ = store.delete(id).map_err(to_rustler_err)?;
    }

    Ok(result)
}

pub(crate) fn create_or_reuse_store(
    js: &JetStream,
    name: &str,
) -> Result<ObjectStore, Box<dyn std::error::Error>> {
    match js.object_store(name) {
        Ok(os) => Ok(os),
        Err(_) => js
            .create_object_store(&Config {
                bucket: name.to_string(),
                ..Default::default()
            })
            .map_err(|e| format!("Failed to create store: {}", e).into()),
    }
}
