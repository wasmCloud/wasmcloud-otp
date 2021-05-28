use data_encoding::HEXUPPER;
use ring::digest::{Context, Digest, SHA256};
use rmp_serde::Deserializer;
use rmp_serde::Serializer;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt::Display;
use std::io::Cursor;
use std::io::Read;
use std::string::ToString;
use uuid::Uuid;
use wascap::prelude::{Claims, KeyPair};

use crate::Result;

pub(crate) const URL_SCHEME: &str = "wasmbus";
pub(crate) const SYSTEM_ACTOR: &str = "system";
pub(crate) const OP_HALT: &str = "__halt";

/// An immutable representation of an invocation within wasmcloud
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[doc(hidden)]
pub struct Invocation {
    pub origin: WasmCloudEntity,
    pub target: WasmCloudEntity,
    pub operation: String,
    pub msg: Vec<u8>,
    pub id: String,
    pub encoded_claims: String,
    pub host_id: String,
}

impl Invocation {
    /// Creates a new invocation. All invocations are signed with the host key as a way
    /// of preventing them from being forged over the network when connected to a lattice,
    /// so an invocation requires a reference to the host (signing) key
    pub fn new(
        hostkey: &KeyPair,
        origin: WasmCloudEntity,
        target: WasmCloudEntity,
        op: &str,
        msg: Vec<u8>,
    ) -> Invocation {
        let subject = format!("{}", Uuid::new_v4());
        let issuer = hostkey.public_key();
        let target_url = format!("{}/{}", target.url(), op);
        let claims = Claims::<wascap::prelude::Invocation>::new(
            issuer.to_string(),
            subject.to_string(),
            &target_url,
            &origin.url(),
            &invocation_hash(&target_url, &origin.url(), &msg),
        );
        Invocation {
            origin,
            target,
            operation: op.to_string(),
            msg,
            id: subject,
            encoded_claims: claims.encode(&hostkey).unwrap(),
            host_id: issuer,
        }
    }

    /// Produces a host-signed invocation that is used to halt anything that can receive invocations. This invocation
    /// has both an origin and a target of SYSTEM_ACTOR. This has a net effect of making this invocation unroutable
    /// across a lattice, and therefore can only be produced internally. In other words, a remote host can't fabricate
    /// a halt invocation and send it to a provider or actor
    pub fn halt(hostkey: &KeyPair) -> Invocation {
        let subject = format!("{}", Uuid::new_v4());
        let issuer = hostkey.public_key();
        let op = OP_HALT.to_string();
        let target = WasmCloudEntity::Actor(SYSTEM_ACTOR.to_string());
        let target_url = format!("{}/{}", target.url(), &op);
        let claims = Claims::<wascap::prelude::Invocation>::new(
            issuer.to_string(),
            subject.to_string(),
            &target_url,
            &target.url(),
            &invocation_hash(&target_url, &target.url(), &[]),
        );
        Invocation {
            origin: target.clone(),
            target,
            operation: op,
            msg: vec![],
            id: subject,
            encoded_claims: claims.encode(&hostkey).unwrap(),
            host_id: issuer,
        }
    }

    /// A fully-qualified URL indicating the origin of the invocation
    pub fn origin_url(&self) -> String {
        self.origin.url()
    }

    /// A fully-qualified URL indicating the target of the invocation
    pub fn target_url(&self) -> String {
        format!("{}/{}", self.target.url(), self.operation)
    }

    /// The hash of the invocation's target, origin, and raw bytes
    pub fn hash(&self) -> String {
        invocation_hash(&self.target_url(), &self.origin_url(), &self.msg)
    }

    /// Validates the current invocation to ensure that the invocation claims have
    /// not been forged, are not expired, etc
    pub fn validate_antiforgery(&self) -> Result<()> {
        let vr = wascap::jwt::validate_token::<wascap::prelude::Invocation>(&self.encoded_claims)
            .map_err(|e| format!("{}", e))?;
        let claims = Claims::<wascap::prelude::Invocation>::decode(&self.encoded_claims)
            .map_err(|e| format!("{}", e))?;
        if vr.expired {
            return Err("Invocation claims token expired".into());
        }
        if !vr.signature_valid {
            return Err("Invocation claims signature invalid".into());
        }
        if vr.cannot_use_yet {
            return Err("Attempt to use invocation before claims token allows".into());
        }
        let inv_claims = claims.metadata.unwrap();
        if inv_claims.invocation_hash != self.hash() {
            return Err("Invocation hash does not match signed claims hash".into());
        }
        if claims.subject != self.id {
            return Err("Subject of invocation claims token does not match invocation ID".into());
        }
        if claims.issuer != self.host_id {
            return Err("Invocation claims issuer does not match invocation host".into());
        }
        if inv_claims.target_url != self.target_url() {
            return Err("Invocation claims and invocation target URL do not match".into());
        }
        if inv_claims.origin_url != self.origin_url() {
            return Err("Invocation claims and invocation origin URL do not match".into());
        }

        Ok(())
    }
}

/// The response to an invocation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[doc(hidden)]
pub struct InvocationResponse {
    pub msg: Vec<u8>,
    pub error: Option<String>,
    pub invocation_id: String,
}

impl InvocationResponse {
    /// Creates a successful invocation response. All invocation responses contain the
    /// invocation ID to which they correlate
    pub fn success(inv: &Invocation, msg: Vec<u8>) -> InvocationResponse {
        InvocationResponse {
            msg,
            error: None,
            invocation_id: inv.id.to_string(),
        }
    }

    /// Creates an error response
    pub fn error(inv: &Invocation, err: &str) -> InvocationResponse {
        InvocationResponse {
            msg: Vec::new(),
            error: Some(err.to_string()),
            invocation_id: inv.id.to_string(),
        }
    }
}

/// Represents an entity within the host runtime that can be the source
/// or target of an invocation
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Eq, Hash)]
#[doc(hidden)]
pub enum WasmCloudEntity {
    Actor(String),
    Capability {
        id: String,
        contract_id: String,
        link_name: String,
    },
}

impl Display for WasmCloudEntity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.url())
    }
}

impl WasmCloudEntity {
    /// The URL of the entity
    pub fn url(&self) -> String {
        match self {
            WasmCloudEntity::Actor(pk) => format!("{}://{}", URL_SCHEME, pk),
            WasmCloudEntity::Capability {
                id,
                contract_id,
                link_name,
            } => format!(
                "{}://{}/{}/{}",
                URL_SCHEME,
                contract_id
                    .replace(":", "/")
                    .replace(" ", "_")
                    .to_lowercase(),
                link_name.replace(" ", "_").to_lowercase(),
                id
            ),
        }
    }

    /// The unique (public) key of the entity
    pub fn key(&self) -> String {
        match self {
            WasmCloudEntity::Actor(pk) => pk.to_string(),
            WasmCloudEntity::Capability { id, .. } => id.to_string(),
        }
    }
}

/// A link definition is the description of a connection between an actor
/// and a capability provider, along with the set of configuration values
/// that belong to that connection
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct LinkDefinition {
    pub actor_id: String,
    pub provider_id: String,
    pub link_name: String,
    pub contract_id: String,
    pub values: std::collections::HashMap<String, String>,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct LinkDefinitionList {
    pub link_definitions: Vec<LinkDefinition>,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct ClaimsList {
    #[serde(default)]
    pub claims: Vec<Claims<wascap::prelude::Actor>>,
}

/// A mapping of an alias (OCI or call alias) to a target entity
#[derive(Debug, PartialEq, Deserialize, Serialize, Clone)]
pub struct ReferenceMap {
    pub kind: ReferenceType,
    pub target: WasmCloudEntity,
}

/// Indicates the type of reference map (alias)
#[derive(Debug, PartialEq, Deserialize, Serialize, Clone)]
pub enum ReferenceType {
    OCI(String),
    CallAlias(String),
}

impl LinkDefinition {
    pub fn new(
        actor: &str,
        provider: &str,
        link: &str,
        contract: &str,
        values: HashMap<String, String>,
    ) -> LinkDefinition {
        LinkDefinition {
            actor_id: actor.to_string(),
            provider_id: provider.to_string(),
            link_name: link.to_string(),
            contract_id: contract.to_string(),
            values,
        }
    }
}

fn sha256_digest<R: Read>(mut reader: R) -> Result<Digest> {
    let mut context = Context::new(&SHA256);
    let mut buffer = [0; 1024];

    loop {
        let count = reader.read(&mut buffer).map_err(|e| format!("{}", e))?;
        if count == 0 {
            break;
        }
        context.update(&buffer[..count]);
    }

    Ok(context.finish())
}

pub(crate) fn invocation_hash(target_url: &str, origin_url: &str, msg: &[u8]) -> String {
    use std::io::Write;
    let mut cleanbytes: Vec<u8> = Vec::new();
    cleanbytes.write_all(origin_url.as_bytes()).unwrap();
    cleanbytes.write_all(target_url.as_bytes()).unwrap();
    cleanbytes.write_all(msg).unwrap();
    let digest = sha256_digest(cleanbytes.as_slice()).unwrap();
    HEXUPPER.encode(digest.as_ref())
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
