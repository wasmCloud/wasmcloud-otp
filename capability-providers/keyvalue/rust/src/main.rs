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

lazy_static! {
    static ref LINKDEFS: RwLock<HashMap<String, LinkDefinition>> = RwLock::new(HashMap::new());
}

use crossbeam::sync::Parker;
use rmp_serde::{Deserializer, Serializer};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::Cursor;
use std::result::Result;
use std::sync::RwLock;

mod kvredis;

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
    // may not need this since the host doesn't use it in the Rust invocation
    //#[serde(with = "serde_bytes")]
    pub msg: Vec<u8>,
    pub id: String,
    pub encoded_claims: String,
    pub host_id: String,
}

fn main() -> Result<(), String> {
    let _ = env_logger::try_init();
    info!("Starting Redis Capability Provider");

    let provider_key = "Vxxxx"; // TODO: get from env/wasmcloud host
    let link_name = "default"; // TODO: get from env/wasmcloud host

    let ldget_topic = format!(
        "wasmbus.rpc.default.{}.{}.linkdefs.get",
        provider_key, link_name
    );
    let lddel_topic = format!(
        "wasmbus.rpc.default.{}.{}.linkdefs.del",
        provider_key, link_name
    );
    let ldput_topic = format!(
        "wasmbus.rpc.default.{}.{}.linkdefs.put",
        provider_key, link_name
    );
    let shutdown_topic = format!(
        "wasmbus.rpc.default.{}.{}.shutdown",
        provider_key, link_name
    );
    let rpc_topic = format!("wasmbus.rpc.default.{}.{}", provider_key, link_name);

    let nc = nats::connect("0.0.0.0:4222").map_err(|e| format!("{}", e))?; // TODO: get real nats address and credentials from the host/env

    let _sub = nc
        .queue_subscribe(&ldget_topic, &ldget_topic)
        .map_err(|e| format!("{}", e))?
        .with_handler(move |msg| {
            println!("Received {}", &msg);
            msg.respond(serialize(&*LINKDEFS.read().unwrap()).unwrap())
                .unwrap();
            Ok(())
        });

    let _sub = nc
        .subscribe(&lddel_topic)
        .map_err(|e| format!("{}", e))?
        .with_handler(move |msg| {
            let ld: LinkDefinition = deserialize(&msg.data).unwrap();
            LINKDEFS.write().unwrap().remove(&ld.actor_id);
            println!("Received {}", &msg);
            Ok(())
        });

    let _sub = nc
        .subscribe(&ldput_topic)
        .map_err(|e| format!("{}", e))?
        .with_handler(move |msg| {
            let ld: LinkDefinition = deserialize(&msg.data).unwrap();
            LINKDEFS
                .write()
                .unwrap()
                .insert(ld.actor_id.to_string(), ld);
            println!("Received {}", &msg);
            Ok(())
        });

    let p = Parker::new();
    let u = p.unparker().clone();

    let _sub = nc
        .subscribe(&shutdown_topic)
        .map_err(|e| format!("{}", e))?
        .with_handler(move |_msg| {
            info!("Received termination signal. Shutting down capability provider.");
            u.unpark();
            Ok(())
        });

    // TODO: Add RPC handling for all the k/v ops (e.g. add, sadd, del, get, etc)
    let _sub = nc
        .subscribe(&rpc_topic)
        .map_err(|e| format!("{}", e))?
        .with_handler(move |msg| {
            println!("Received {}", &msg);
            Ok(())
        });

    info!("Ready");
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
