//! # wasmCloud Redis Provider
//!
//! Topics relevant to a capability provider:
//!
//! RPC:
//!   * wasmbus.rpc.{prefix}.{provider_key}.{link_name} - Get Invocation, answer InvocationResponse
//!   * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.get - Query all link defs for this provider. (queue subscribed)
//!   * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.del - Remove a link def. Provider de-provisions resources for the given actor.
//!   * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.put - Puts a link def. Provider provisions resources for the given actor.
//!   * wasmbus.rpc.{prefix}.{public_key}.{link_name}.shutdown - Request for graceful shutdown

#[macro_use]
extern crate log;
#[macro_use]
extern crate lazy_static;

mod generated;
mod kvredis;
mod rpc;

use std::io::{self, BufRead, Read};

const YEET: &str = "YEET";

lazy_static! {
    static ref LINKDEFS: RwLock<HashMap<String, LinkDefinition>> = RwLock::new(HashMap::new());
    static ref CLIENTS: RwLock<HashMap<String, redis::Client>> = RwLock::new(HashMap::new());
}

use anyhow::Result;
use crossbeam::sync::Parker;
use rmp_serde::{Deserializer, Serializer};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::Cursor;
use std::sync::RwLock;

#[derive(Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LinkDefinition {
    pub actor_id: String,
    pub provider_id: String,
    pub link_name: String,
    pub contract_id: String,
    pub values: HashMap<String, String>,
}

#[derive(Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WasmCloudEntity {
    pub public_key: String,
    pub link_name: String,
    pub contract_id: String,
}

#[derive(Default, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Invocation {
    pub origin: WasmCloudEntity,
    pub target: WasmCloudEntity,
    pub operation: String,
    // I believe we determined this is necessary to properly round trip the "bytes"
    // type with Elixir so it doesn't treat it as a "list of u8s"
    #[serde(with = "serde_bytes")]
    pub msg: Vec<u8>,
    pub id: String,
    pub encoded_claims: String,
    pub host_id: String,
}

/// The response to an invocation
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct InvocationResponse {
    // I believe we determined this is necessary to properly round trip the "bytes"
    // type with Elixir so it doesn't treat it as a "list of u8s"
    #[serde(with = "serde_bytes")]
    pub msg: Vec<u8>,
    pub error: Option<String>,
    pub invocation_id: String,
    pub instance_id: String,
}

impl InvocationResponse {
    pub fn failure(inv: &Invocation, e: &str) -> InvocationResponse {
        InvocationResponse {
            error: Some(e.to_string()),
            invocation_id: inv.id.to_string(),
            instance_id: YEET.into(),
            ..Default::default()
        }
    }

    /// Creates a successful invocation response. All invocation responses contain the
    /// invocation ID to which they correlate
    pub fn success(msg: impl Serialize) -> InvocationResponse {
        InvocationResponse {
            invocation_id: YEET.into(), // to be filled in later,
            instance_id: YEET.into(),
            msg: serialize(&msg).unwrap(),
            error: None,
        }
    }
}

/// The data supplied by the host at start time via stdin
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct HostData {
    pub host_id: String,
    #[serde(default)]
    pub lattice_rpc_prefix: String,
    #[serde(default)]
    pub link_name: String,
    #[serde(default)]
    pub lattice_rpc_user_jwt: String,
    #[serde(default)]
    pub lattice_rpc_user_seed: String,
    #[serde(default)]
    pub lattice_rpc_url: String,
    #[serde(default)]
    pub provider_key: String,
    #[serde(default)]
    pub env_values: HashMap<String, String>,
    #[serde(default)]
    pub invocation_seed: String,
    #[serde(default)]
    pub instance_id: String,
}

fn main() -> Result<()> {
    let _ = env_logger::try_init();

    // Host data is a JSON object that is base64 encoded
    let stdin = io::stdin();
    let mut handle = stdin.lock();
    let mut host_data_enc = String::new();
    handle.read_line(&mut host_data_enc)?;
    let host_data_dec = base64::decode(host_data_enc.trim_end())?;
    let host_data: HostData = serde_json::from_slice(&host_data_dec)?;

    let provider_key = host_data.provider_key;
    let link_name = host_data.link_name;
    let lattice_rpc_prefix = host_data.lattice_rpc_prefix;
    let instance_id = host_data.instance_id;

    info!("Starting Redis Capability Provider {}", provider_key);

    let ldget_topic = format!(
        "wasmbus.rpc.{}.{}.{}.linkdefs.get",
        lattice_rpc_prefix, provider_key, link_name
    );
    let lddel_topic = format!(
        "wasmbus.rpc.{}.{}.{}.linkdefs.del",
        lattice_rpc_prefix, provider_key, link_name
    );
    let ldput_topic = format!(
        "wasmbus.rpc.{}.{}.{}.linkdefs.put",
        lattice_rpc_prefix, provider_key, link_name
    );
    let shutdown_topic = format!(
        "wasmbus.rpc.{}.{}.{}.shutdown",
        lattice_rpc_prefix, provider_key, link_name
    );
    let rpc_topic = format!(
        "wasmbus.rpc.{}.{}.{}",
        lattice_rpc_prefix, provider_key, link_name
    );

    let health_topic = format!(
        "wasmbus.rpc.{}.{}.{}.health",
        lattice_rpc_prefix, provider_key, link_name
    );

    let nc = nats::connect(&host_data.lattice_rpc_url)?; // TODO: use credentials from the host_data struct

    let _sub = nc
        .queue_subscribe(&ldget_topic, &ldget_topic)?
        .with_handler(move |msg| {
            println!("Received request for linkdefs.");
            msg.respond(serialize(&*LINKDEFS.read().unwrap()).unwrap())
                .unwrap();
            Ok(())
        });

    let _sub = nc
        .subscribe(&health_topic)?
        .with_handler(move |msg| {
            println!("Received health check request.");
            msg.respond(serialize(vec![true]).unwrap())
                .unwrap();
            Ok(())
        });

    let _sub = nc.subscribe(&lddel_topic)?.with_handler(move |msg| {
        let ld: LinkDefinition = deserialize(&msg.data).unwrap();
        LINKDEFS.write().unwrap().remove(&ld.actor_id);
        CLIENTS.write().unwrap().remove(&ld.actor_id);
        println!(
            "Deleted link definition from {} to {}",
            ld.actor_id, ld.provider_id
        );

        Ok(())
    });

    let _sub = nc.subscribe(&ldput_topic)?.with_handler(move |msg| {
        let ld: LinkDefinition = deserialize(&msg.data).unwrap();
        if LINKDEFS.read().unwrap().contains_key(&ld.actor_id) {
            warn!(
                "Received LD put for existing link definition from {} to {}",
                ld.actor_id, ld.provider_id
            );
            return Ok(());
        }
        LINKDEFS
            .write()
            .unwrap()
            .insert(ld.actor_id.to_string(), ld.clone());

        let conn = kvredis::initialize_client(ld.values.clone())
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
        CLIENTS
            .write()
            .unwrap()
            .insert(ld.actor_id.to_string(), conn);
        println!(
            "Added link definition from {} to {}",
            ld.actor_id, ld.provider_id
        );

        Ok(())
    });

    let p = Parker::new();
    let u = p.unparker().clone();

    let _sub = nc.subscribe(&shutdown_topic)?.with_handler(move |msg| {
        println!("Received termination signal. Shutting down capability provider.");
        u.unpark();
        let _ = msg.respond("Redis provider shutdown successfully");
        Ok(())
    });

    // TODO: Add RPC handling for all the k/v ops (e.g. add, sadd, del, get, etc)
    let _sub = nc.subscribe(&rpc_topic)?.with_handler(move |msg| {
        let inv: Invocation = deserialize(&msg.data).unwrap();
        println!("Received RPC invocation");
        let ir = rpc::handle_rpc(inv, instance_id.clone());
        let _ = msg.respond(
            serialize(&ir).map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?,
        );
        Ok(())
    });

    println!("Redis provider is ready for requests");
    p.park();

    Ok(())
}

/// The agreed-upon standard for payload serialization (message pack)
pub fn serialize<T>(
    item: T,
) -> ::std::result::Result<Vec<u8>, Box<dyn std::error::Error + Send + Sync>>
where
    T: Serialize,
{
    let mut buf = Vec::new();
    item.serialize(&mut Serializer::new(&mut buf).with_struct_map())?;
    Ok(buf)
}

/// The agreed-upon standard for payload de-serialization (message pack)
pub fn deserialize<'de, T: Deserialize<'de>>(
    buf: &[u8],
) -> ::std::result::Result<T, Box<dyn std::error::Error + Send + Sync>> {
    let mut de = Deserializer::new(Cursor::new(buf));
    match Deserialize::deserialize(&mut de) {
        Ok(t) => Ok(t),
        Err(e) => Err(format!("Failed to de-serialize: {}", e).into()),
    }
}
