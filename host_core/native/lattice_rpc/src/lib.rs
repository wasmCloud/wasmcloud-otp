#[macro_use]
extern crate rustler;

use rpcclient::{serialize, LatticeRpcClient};
use rustler::{Binary, Encoder, Env, Error, Term};

mod atoms {
    rustler_atoms! {
        atom ok;
        //atom error;
        //atom __true__ = "true";
        //atom __false__ = "false";
    }
}

rustler::rustler_export_nifs! {
    "Elixir.HostCore.Lattice.RpcClient",
    [
        ("perform_invocation", 9, perform_invocation)
    ],
    None
}

// Yes, this is copied and not re-used. Yes, it's worth it.
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

/// This function takes parameters required for creating an invocation, publishes the invocation request
/// on the appropriate topic, and then obtains the binary results and passes them back up to Elixir. The
/// Elixir code never has to see or decode the inside of the payloads.
/// # Parameters
/// * `actor` - The public key of the actor
/// * `binding` - The name of the binding/link definition
/// * `namespace` - The namespace of the operation (e.g. `wasmcloud:httpserver` for providers, `Mxxx` for actor targets)
/// * `operation` - The name of the operation to be performed
/// * `payload` - Raw binary payload
/// * `claims` - Claims of the actor in question
/// * `seed` - The seed key required for signing an invocation
/// * `prefix` - The lattice namespace prefix for the current connection
fn perform_invocation<'a>(env: Env<'a>, args: &[Term<'a>]) -> Result<Term<'a>, rustler::Error> {
    let actor: String = args[0].decode()?;
    let mut binding: String = args[1].decode()?;
    let namespace: String = args[2].decode()?;
    let operation: String = args[3].decode()?;
    let payload: Binary = args[4].decode()?;
    let bytes = payload.as_slice();
    let claims: Claims = args[5].decode()?;
    let seed: String = args[6].decode()?;
    let prefix: String = args[7].decode()?;
    let provider_key: String = args[8].decode()?;

    if binding.is_empty() {
        binding = "default".to_string();
    }

    // TODO: reuse an existing connection
    let c = nats::connect("127.0.0.1")
        .map_err(|_e| rustler::Error::Atom("Failed to establish NATS connection"))?;

    let lc = LatticeRpcClient::new(c);
    let res = lc.perform_invocation(
        &actor,
        &binding,
        &operation,
        &namespace,
        bytes,
        &seed,
        &prefix,
        &provider_key,
    );
    let resbytes = serialize(res)
        .map_err(|e| rustler::Error::Atom("Failed to serialize invocation result"))?;
    Ok(resbytes.encode(env))
}

fn is_actor(ns: &str) -> bool {
    ns.len() == 56 && ns.starts_with("M")
}
