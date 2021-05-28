#[macro_use]
extern crate rustler;

use rustler::{Binary, Encoder, Env, Term};
use wascap::prelude::*;
use nkeys::KeyPair;

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

mod atoms;

/*

   N - Server
   C - Cluster
   O - Operator
   A - Account
   U - User
   M - Module
   V - Service / Service Provider
   P - Private Key
*/

rustler::rustler_export_nifs! {
    "Elixir.HostCore.WasmCloud.Native",
    [
        ("extract_claims", 1, extract_claims),
        ("generate_key", 1, generate_key)
    ],
    None
}

/// Extracts the claims from the raw bytes of a _signed_ WebAssembly module/actor and returns them
/// in the form of a simple struct that will bubble its way up to Elixir as a native struct
fn extract_claims<'a>(env: Env<'a>, args: &[Term<'a>]) -> Result<Term<'a>, rustler::Error> {
    let binary: Binary = args[0].decode()?;
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

    Ok(out.encode(env))
}

#[derive(Debug, Copy, Clone)]
pub enum KeyType {
    Server,
    Cluster,
    Operator,
    Account,
    User,
    Module,
    Provider,
}


fn generate_key<'a>(env: Env<'a>, args: &[Term<'a>]) -> Result<Term<'a>, rustler::Error> {
    let key_type = keytype_from_term(&args[0])?;
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

    Ok((pk, seed).encode(env))
}

fn keytype_from_term(term: &Term) -> Result<KeyType, rustler::Error> {
    let key_type = term
        .atom_to_string()
        .map_err(|_| rustler::Error::RaiseTerm(Box::new("Must be given a valid key type atom.")))?;

    Ok(match key_type.as_str() {
        "server" => KeyType::Server,
        "cluster" => KeyType::Cluster,
        "operator" => KeyType::Operator,
        "account" => KeyType::Account,
        "user" => KeyType::User,
        "module" => KeyType::Module,
        "provider" => KeyType::Provider,
        _ => {
            return Err(rustler::Error::RaiseTerm(Box::new(
                "Key type must be one of `server`, `cluster`, `operator`, `account`, `user`, `module`, or `provider`.",
            )))
        }    
    })
}
