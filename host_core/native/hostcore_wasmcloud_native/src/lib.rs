#[macro_use]
extern crate rustler;

use nkeys::KeyPair;
use rustler::Binary;
use rustler::Error;
use wascap::prelude::*;

#[derive(NifStruct)]
#[module = "HostCore.WasmCloud.Native.Claims"]
pub struct Claims {
    public_key: String,
    issuer: String,
    name: Option<String>,
    call_alias: Option<String>,
    version: Option<String>,
    revision: Option<i32>,
    tags: Option<Vec<String>>,
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

mod atoms;

rustler::init!(
    "Elixir.HostCore.WasmCloud.Native",
    [extract_claims, generate_key]
);

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
