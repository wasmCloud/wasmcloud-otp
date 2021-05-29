#[macro_use]
extern crate rustler;

use rpcclient::{serialize, LatticeRpcClient};
use rustler::{Binary, Encoder, Env, Error, Term};

mod atoms {
    rustler::atoms! {
        ok
        //atom error;
        //atom __true__ = "true";
        //atom __false__ = "false";
    }
}

rustler::init!("Elixir.HostCore.Lattice.RpcClient", [perform_invocation]);

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
#[rustler::nif]
fn perform_invocation<'a>(
    actor: String,
    binding: String,
    namespace: String,
    operation: String,
    payload: Binary,
    _claims: Claims,
    seed: String,
    prefix: String,
    provider_key: String,
) -> Result<Vec<u8>, Error> {
    let mut binding = binding.clone();
    let bytes = payload.as_slice();

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
        .map_err(|_e| rustler::Error::Atom("Failed to serialize invocation result"))?;
    Ok(resbytes)
}
