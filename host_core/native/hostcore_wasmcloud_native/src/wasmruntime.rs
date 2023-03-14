use anyhow::{self, bail, ensure, Context};
use futures::executor::block_on;
use log::info;
use rustler::{Binary, Env, Error, ResourceArc};
use std::hash::BuildHasher;
use std::sync::Mutex;
use wascap::jwt;
use wasmcloud::capability::{Handler, HostHandler, LogLogging, RandNumbergen};
use wasmcloud::{ActorModule, Runtime as WcRuntime};
//use wasmcloud::{ActorInstanceConfig, ActorModule, ActorResponse, Runtime};

type WasmcloudRuntime = WcRuntime<
    HostHandler<
        LogLogging<&'static dyn ::log::Log>,
        RandNumbergen<::rand::rngs::OsRng>,
        ElixirHandler,
    >,
>;

pub struct ElixirHandler {}

impl wasmcloud::capability::Handler for ElixirHandler {
    type Error = anyhow::Error;

    fn handle(
        &self,
        claims: &jwt::Claims<jwt::Actor>,
        binding: String,
        namespace: String,
        operation: String,
        payload: Option<Vec<u8>>,
    ) -> anyhow::Result<Result<Option<Vec<u8>>, Self::Error>> {
        bail!(
            "cannot execute `{binding}.{namespace}.{operation}` with payload {payload:?} for actor `{}`",
            claims.subject
        )
    }
}

pub struct RuntimeResource {
    //pub inner: WasmcloudRuntime<Box<dyn Handler<Error = String>>>,
    pub inner: WasmcloudRuntime,
}

pub struct ActorResource {
    //pub inner:  Mutex<wasmcloud::actor::Instance>
    pub raw: Vec<u8>,
}

#[derive(NifStruct)]
#[module = "HostCore.WasmCloud.Runtime.Config"]
pub struct ExRuntimeConfig {
    placeholder: bool,
}

pub fn on_load(env: Env) -> bool {
    rustler::resource!(RuntimeResource, env);
    rustler::resource!(ActorResource, env);
    true
}

#[rustler::nif(name = "runtime_new")]
pub fn new(config: ExRuntimeConfig) -> Result<ResourceArc<RuntimeResource>, rustler::Error> {
    let handler = HostHandler {
        logging: LogLogging::from(log::logger()),
        numbergen: RandNumbergen::from(rand::rngs::OsRng),
        hostcall: ElixirHandler {},
    };

    let rt: WasmcloudRuntime = WasmcloudRuntime::builder(handler)
        .try_into()
        .context("failed to construct runtime")
        .map_err(|e| Error::Term(Box::new(e.to_string())))?;

    let resource = ResourceArc::new(RuntimeResource { inner: rt });
    Ok(resource)
}

#[rustler::nif(name = "version")]
pub fn version(runtime_resource: ResourceArc<RuntimeResource>) -> Result<String, rustler::Error> {
    let v = runtime_resource.inner.version();

    Ok(v.to_string())
}

#[rustler::nif(name = "start_actor")]
pub fn start_actor<'a>(
    env: rustler::Env<'a>,
    runtime_resource: ResourceArc<RuntimeResource>,
    bytes: Binary<'a>,
) -> Result<ResourceArc<ActorResource>, rustler::Error> {
    // let engine: &Engine = &*(engine_resource.inner.lock().map_err(|e| {
    //     rustler::Error::Term(Box::new(format!("Could not unlock engine resource: {}", e)))
    // })?);

    // let module = ActorModule::new(&runtime_resource.inner, bytes.as_slice())
    // .context("failed to load actor from bytes")
    // .unwrap();
    // let actor = block_on(async move {
    //    let m = module.clone();
    //     let instance = m.instantiate().await.unwrap();

    //     instance
    // });

    // let resource = ResourceArc::new(ActorResource {
    //     raw: bytes.to_vec(),
    // });
    // Ok(resource)

    Ok(ResourceArc::new(ActorResource { raw: vec![1, 2, 3] }))
}

#[rustler::nif(name = "call_actor")]
pub fn call_actor<'a>(
    env: rustler::Env<'a>,
    instance: ResourceArc<ActorResource>,
    operation: &str,
    payload: Binary<'a>,
) -> Result<Binary<'a>, rustler::Error> {
    /*
    ActorModule::new(&rt, actor)
        .context("failed to create actor")?
        .instantiate()
        .context("failed to instantiate actor")? */
    todo!()
}
/*

#[rustler::nif(name = "engine_precompile_module")]
pub fn precompile_module<'a>(
    env: rustler::Env<'a>,
    engine_resource: ResourceArc<EngineResource>,
    binary: Binary<'a>,
) -> Result<Binary<'a>, rustler::Error> {
    let engine: &Engine = &*(engine_resource.inner.lock().map_err(|e| {
        rustler::Error::Term(Box::new(format!("Could not unlock engine resource: {}", e)))
    })?);
    let bytes = binary.as_slice();
    let serialized_module = engine.precompile_module(bytes).map_err(|err| {
        rustler::Error::Term(Box::new(format!("Could not precompile module: {}", err)))
    })?;
    let mut binary = OwnedBinary::new(serialized_module.len())
        .ok_or_else(|| rustler::Error::Term(Box::new("not enough memory")))?;
    binary.copy_from_slice(&serialized_module);
    Ok(binary.release(env))
} */
