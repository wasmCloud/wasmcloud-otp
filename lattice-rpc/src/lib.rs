#![doc(html_favicon_url = "https://wasmcloud.com/favicon.ico")]
#![doc(html_logo_url = "https://wasmcloud.com/images/screenshots/Wasmcloud.Icon_Green_704x492.png")]

//! # Lattice RPC Client
//!
//! The lattice  RPC client provides a wrapper around some basic NATS interactions that
//! represent the protocol used for invoking actors and capability providers, establishing links
//! between providers and actors, publishing claims to be cached, and publishing reference mappings
//! such as call aliases and OCI references.

use std::collections::HashMap;

use dispatch::{ClaimsList, LinkDefinitionList};
use nats::Subscription;
use wascap::prelude::KeyPair;

mod dispatch;

pub use dispatch::{deserialize, serialize};
pub use dispatch::{
    Invocation, InvocationResponse, LinkDefinition, ReferenceMap, ReferenceType, WasmCloudEntity,
};
pub use wascap::prelude::Claims;

/// All lattice RPC errors return strings upon failure
pub type Result<T> = std::result::Result<T, String>;

/// Provides a client interface to the standard lattice protocols
/// for remotely communicating with actors (via host proxy) and
/// freestanding capability providers. This client does not include
/// any of the "control interface" functionality, and is only to be used
/// to perform invocations and operations supporting invocations over
/// lattice.
///
/// # Message Broker
/// This client provides an abstraction over the following
/// topics:
/// * `wasmbus.rpc.{prefix}.{public_key}` - Send invocations to an actor Invocation->InvocationResponse
/// * `wasmbus.rpc.{prefix}.{public_key}.{link_name}` - Send invocations (from actors only) to Providers  Invocation->InvocationResponse
/// * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.put` - Publish link definition (e.g. bind to an actor)
/// * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.get` - Query all link defss for this provider. (queue subscribed)
/// * `wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.del` - Remove a link def.                                                            
/// * `wasmbus.rpc.{prefix}.claims.put` - Publish discovered claims
/// * `wasmbus.rpc.{prefix}.claims.get` - Query all claims (queue subscribed by hosts)
/// * `wasmbus.rpc.{prefix}.refmaps.put` - Publish a reference map, e.g. OCI ref -> PK, call alias -> PK
/// * `wasmbus.rpc.{prefix}.refmaps.get` - Query all reference maps (queue subscribed by hosts)    
///
#[derive(Clone, Debug)]
pub struct LatticeRpcClient {
    nc: nats::Connection,
}

impl LatticeRpcClient {
    /// Creates a new lattice RPC client with a NATS connection to the lattice
    pub fn new(nc: nats::Connection) -> LatticeRpcClient {
        LatticeRpcClient { nc }
    }

    /// Performs an invocation that can either target an actor or a capability provider.
    /// It is up to the caller to ensure that all of the various arguments make sense for this
    /// invocation, otherwise it will fail.
    ///
    /// # Arguments
    /// * `actor_key` - The public key of the actor performing the invocation. If the invocation is coming from a provider, this argument is ignored.
    /// * `binding` - The link name for the invocation. This will be ignored in actor-to-actor calls.
    /// * `namespace` - The namespace of the operation. For provider calls, this will be something like `wasmcloud:messaging`. For actor targets, this is the public key of the target actor
    /// * `payload` - The raw bytes of the payload to be placed _inside_ the invocation envelope. Do **not** serialize an invocation for this parameter, one is created for you.
    /// * `seed` - The seed signing key of the host, used for invocation anti-forgery tokens.
    /// * `prefix` - The lattice subject prefix of the lattice into which this invocation is being sent.
    /// * `provider_key` - The public key of the capability provider involved in this invocation. This value will be ignored for actor targets.
    pub fn perform_invocation(
        &self,
        actor_key: &str,
        binding: &str,
        operation: &str,
        namespace: &str,
        payload: &[u8],
        seed: &str,
        prefix: &str,
        provider_key: &str,
    ) -> Result<InvocationResponse> {
        let mut binding = binding.clone();
        if binding.is_empty() {
            binding = "default";
        }

        let (_topic, target, origin) = if namespace.len() == 56 && binding.starts_with("M") {
            // target is an actor
            // origin can be an actor or a provider
            (
                format!("wasmbus.rpc.{}.{}", prefix, binding),
                WasmCloudEntity::Actor(namespace.to_string()),
                if actor_key.starts_with("M") {
                    WasmCloudEntity::Actor(actor_key.to_string())
                } else {
                    WasmCloudEntity::Capability {
                        contract_id: namespace.to_string(),
                        id: provider_key.to_string(),
                        link_name: binding.to_string(),
                    }
                },
            )
        } else {
            // target is a provider
            // providers may never call providers, so the origin
            // of a provider-target call MUST be an actor.
            (
                format!("wasmbus.rpc.{}.{}.{}", prefix, namespace, provider_key),
                WasmCloudEntity::Capability {
                    contract_id: namespace.to_string(),
                    id: provider_key.to_string(),
                    link_name: binding.to_string(),
                },
                WasmCloudEntity::Actor(actor_key.to_string()),
            )
        };
        let hostkey = KeyPair::from_seed(seed).unwrap();

        let inv = Invocation::new(&hostkey, origin, target, operation, payload.to_vec());

        Ok(match self.nc.request("foo", "Help me?") {
            Ok(resp) => {
                deserialize::<InvocationResponse>(&resp.data).map_err(|e| format!("{}", e))?
            }
            Err(e) => InvocationResponse::error(&inv, &format!("RPC failure: {}", e)),
        })
    }

    /// Publishes a link definition to the lattice for both caching and processing. Any capability provider
    /// with the matching identity triple (key, contract, and link name) will process the link definition idempotently. If
    /// the definition exists, nothing new will happen.
    ///
    /// This function does not return a success indicator for the link processing, only an indicator for
    /// whether the link definition publication was successful.
    ///
    /// # Arguments
    /// * `actor` - The public key of the actor
    /// * `provider_key` - Public key of the capability provider
    /// * `link_name` - Name of the link used when the target provider was loaded
    /// * `prefix` - Lattice namespace prefix
    /// * `contract_id` - Contract ID of the capability provider
    pub fn put_link_definition(
        &self,
        actor: &str,
        provider_key: &str,
        link_name: &str,
        contract_id: &str,
        prefix: &str,
        values: HashMap<String, String>,
    ) -> Result<()> {
        let ld = LinkDefinition::new(actor, provider_key, link_name, contract_id, values);
        let bytes = serialize(ld).unwrap();

        let topic = format!(
            "wasmbus.rpc.{}.{}.{}.linkdefs.put",
            prefix, provider_key, link_name,
        );

        self.nc
            .publish(&topic, &bytes)
            .map_err(|e| format!("Publication of link definition failed: {}", e))?;

        Ok(())
    }

    /// Removes a link definition from the cache and tells the appropriate provider to
    /// de-activate that link and remove andy resources associated with that link name
    /// from the indicated actor.
    ///
    /// # Arguments
    /// * `actor` - Public key of the actor
    /// * `provider_key` - Public key of the provider
    /// * `link_name` - Link name for the provider
    /// * `contract_id` - Provider's contract ID
    /// * `prefix` - Lattice namespace prefix
    pub fn del_link_definition(
        &self,
        actor: &str,
        provider_key: &str,
        link_name: &str,
        contract_id: &str,
        prefix: &str,
    ) -> Result<()> {
        let ld = LinkDefinition::new(actor, provider_key, link_name, contract_id, HashMap::new());
        let bytes = serialize(ld).unwrap();

        let topic = format!(
            "wasmbus.rpc.{}.{}.{}.linkdefs.del",
            prefix, provider_key, link_name
        );

        self.nc
            .publish(&topic, &bytes)
            .map_err(|e| format!("Publication of link removal failed: {}", e))?;

        Ok(())
    }

    /// Queries the list of link definitions that are active and applied to the indicated
    /// capability provider. This query is done on a queue group topic so if the provider
    /// is horizontally scaled, you will still only get a single response.
    ///
    /// # Arguments
    /// * `prefix` - Lattice namespace prefix
    /// * `provider_key` - Public key of the capability provider
    /// * `link_name` - Link name of the capability provider
    pub fn get_link_definitions(
        &self,
        prefix: &str,
        provider_key: &str,
        link_name: &str,
    ) -> Result<Vec<LinkDefinition>> {
        let topic = format!(
            "wasmbus.rpc.{}.{}.{}.linkdefs.get",
            prefix, provider_key, link_name
        );

        let res = self
            .nc
            .request(&topic, vec![])
            .map_err(|e| format!("Failed to query link definitions: {}", e))?;

        let lds: LinkDefinitionList = deserialize(&res.data).map_err(|e| {
            format!(
                "Could not deserialize results into link definition list: {}",
                e
            )
        })?;

        Ok(lds.link_definitions)
    }

    /// Publishes a set of claims for a given entity. The claims will be cached by all
    /// listening participants in the lattice where applicable.
    ///
    /// # Arguments
    /// * `prefix` - Lattice namespace prefix
    /// * `claims` - Claims to be published
    pub fn put_claims(&self, prefix: &str, claims: Claims<wascap::prelude::Actor>) -> Result<()> {
        let topic = format!("wasmbus.rpc.{}.claims.put", prefix);
        let bytes = serialize(claims).map_err(|e| format!("Failed to serialize claims: {}", e))?;
        let _res = self
            .nc
            .publish(&topic, bytes)
            .map_err(|e| format!("Failed to publish claims put: {}", e))?;

        Ok(())
    }

    /// Queries the distributed cache for all known claims. Note that this list does not
    /// auto-purge when actors and providers are de-scheduled, claims must be manually removed.
    /// As such, it's likely that this list will contain claims for entities that are no
    /// longer up and running. This is as designed.
    ///
    /// # Arguments
    /// * `prefix` - Lattice namespace prefix.
    pub fn get_claims(&self, prefix: &str) -> Result<Vec<Claims<wascap::prelude::Actor>>> {
        let topic = format!("wasmbus.rpc.{}.claims.get", prefix);
        let res = self
            .nc
            .request(&topic, vec![])
            .map_err(|e| format!("Failed to request claims from lattice: {}", e))?;

        let cl: ClaimsList =
            deserialize(&res.data).map_err(|e| format!("Failed to deserialize claims: {}", e))?;

        Ok(cl.claims)
    }

    /// Publishes a reference from an alias (OCI or call alias) to a given WasmCloudEntity. This
    /// reference will be added to the distributed cache and made available to all hosts for
    /// quick lookup. References will be checked before invocations and other administrative
    /// operations wherever possible, falling back on public keys when no reference is found.
    ///
    /// # Arguments
    /// * `prefix` - Lattice namespace prefix
    /// * `source` - The reference to be added (OCI, call alias)
    /// * `target` - The target of the reference (actor, capability provider)
    pub fn put_reference_map(
        &self,
        prefix: &str,
        source: ReferenceType,
        target: WasmCloudEntity,
    ) -> Result<()> {
        let topic = format!("wasmbus.rpc.{}.refmaps.put", prefix);
        let bytes = serialize(ReferenceMap {
            kind: source,
            target,
        })
        .map_err(|e| format!("Failed to serialize reference map: {}", e))?;
        let _res = self
            .nc
            .publish(&topic, bytes)
            .map_err(|e| format!("Failed to publish reference map: {}", e))?;
        Ok(())
    }
}
