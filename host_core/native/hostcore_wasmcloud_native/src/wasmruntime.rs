use anyhow::{self, bail, ensure, Context};
use async_trait::async_trait;
use log::Log;

use crate::TOKIO;
use rustler::{
    dynamic::TermType,
    env::{OwnedEnv, SavedTerm},
    resource::ResourceArc,
    types::tuple::make_tuple,
    types::ListIterator,
    Binary, Encoder, Env, Error, MapIterator, NifResult, Term,
};

use std::{
    sync::{Arc, RwLock},
    thread,
};
use wascap::jwt;
use wasmcloud::{
    capability::{Handler, HostHandler, LogLogging, RandNumbergen},
    ActorComponent,
};
use wasmcloud::{ActorModule, Runtime as WcRuntime};

use crate::{atoms, environment::CallbackTokenResource};
//use wasmcloud::{ActorInstanceConfig, ActorModule, ActorResponse, Runtime};

type MyH = HostHandler<
    LogLogging<&'static dyn ::log::Log>,
    RandNumbergen<::rand::rngs::OsRng>,
    ElixirHandler,
>;

type WasmcloudRuntime = WcRuntime<MyH>;

pub struct ElixirHandler {}

#[async_trait]
impl wasmcloud::capability::Handler for ElixirHandler {
    type Error = anyhow::Error;

    async fn handle(
        &self,
        claims: &jwt::Claims<jwt::Actor>,
        binding: String,
        namespace: String,
        operation: String,
        payload: Option<Vec<u8>>,
    ) -> anyhow::Result<Result<Option<Vec<u8>>, Self::Error>> {
        /*

         let caller_token = set_caller(caller);

        let mut msg_env = OwnedEnv::new();
        msg_env.send_and_clear(&pid.clone(), |env| {
            ....

              (
                atoms::invoke_callback(),
                convert_claims(claims),
                binding,
                namespace,
                operation,
                payload,
                callback_token.clone(),
            )
                .encode(env)
        })
         */
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

// TODO
// pub inner: wasmcloud::actor::ModuleInstance<
//     'static,
//     HostHandler<
//         LogLogging<&'static dyn ::log::Log>,
//         RandNumbergen<::rand::rngs::OsRng>,
//         ElixirHandler,
//     >,
// >,

pub struct ActorResource {
    //pub raw: Vec<u8>,
    //pub instance: wasmcloud::actor::ModuleInstance<'static, MyH>,
    //pub module: wasmcloud::actor::Module<MyH>,
    pub module: wasmcloud::actor::Module<MyH>,
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
pub fn new(_config: ExRuntimeConfig) -> Result<ResourceArc<RuntimeResource>, rustler::Error> {
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

// TODO
// roughly equivalent to the wasmex call_exported_function
#[rustler::nif(name = "start_actor")]
pub fn start_actor<'a>(
    env: rustler::Env<'a>,
    runtime_resource: ResourceArc<RuntimeResource>,
    bytes: Binary<'a>,
) -> Result<ResourceArc<ActorResource>, rustler::Error> {
    // TODO: wrap a wasmcloud::ActorModule in an ActoResource. Right now
    // I can't seem to create an instance with an async closure 🤷🏼

    let module: ActorModule<MyH> = ActorModule::new(&runtime_resource.inner, bytes.as_slice())
        .context("failed to load actor from bytes")
        .unwrap();

    let ar = ActorResource { module };

    Ok(ResourceArc::new(ar))
}

// NOTE: wasmex uses dirtycpu here. should we use dirty IO ?
#[rustler::nif(name = "call_actor", schedule = "DirtyCpu")]
pub fn call_actor<'a>(
    env: rustler::Env<'a>,
    component: ResourceArc<ActorResource>,
    operation: &str,
    payload: Binary<'a>,
    from: Term,
) -> rustler::Atom {
    let pid = env.pid();
    let mut thread_env = OwnedEnv::new();

    let from = thread_env.save(from);
    let payload = payload.to_vec();
    let operation = operation.to_owned();

    println!("HEY THERE");

    // ref: https://github.com/tessi/wasmex/issues/256
    // here we spawn a thread, do the work of the actor invocation,
    // and use other sync mechanisms to finish the work and send
    // the results to the caller (the `from` field)

    // this sends the result of `execute_call_actor` to the pid supplied as the `from` field,
    // which we get from the `from` parameter to the GenServer call that got us here
    thread::spawn(move || {
        thread_env.send_and_clear(&pid, |thread_env| {
            execute_call_actor(thread_env, component, operation.to_string(), payload, from)
        })
    });

    atoms::ok()
}

fn execute_call_actor(
    thread_env: Env,
    component: ResourceArc<ActorResource>,
    operation: String,
    payload: Vec<u8>,
    from: SavedTerm,
) -> Term {
    let from = from
        .load(thread_env)
        .decode::<Term>()
        .unwrap_or_else(|_| "could not load 'from' param".encode(thread_env));

    // for now we instantiate an actor module (cheap) and then immediately call it,
    // disposing of the instance when we're done.
    let response = TOKIO
        .block_on(async {
            let mut instance = component.module.instantiate().await.unwrap();
            instance.call(operation, payload).await
        })
        .unwrap();

    if response.code == 1 {
        // success
        make_tuple(
            thread_env,
            &[
                atoms::returned_function_call().encode(thread_env),
                make_tuple(
                    thread_env,
                    &[
                        atoms::ok().encode(thread_env),
                        response.response.encode(thread_env),
                    ],
                ),
                from,
            ],
        )
    } else {
        // fail
        make_error_tuple(&thread_env, "No response returned", from)
    }
}

fn make_error_tuple<'a>(env: &Env<'a>, reason: &str, from: Term<'a>) -> Term<'a> {
    make_tuple(
        *env,
        &[
            atoms::returned_function_call().encode(*env),
            env.error_tuple(reason),
            from,
        ],
    )
}

// TODO: this is from wasmex... need to convert this so the result is just an optional binary
// called from elixir, params
// * callback_token
// * success: :ok | :error
//   indicates whether the call was successful or produced an elixir-error
// * results: [number]
//   return values of the elixir-callback - empty list when success-type is :error
#[rustler::nif(name = "instance_receive_callback_result")]
pub fn receive_callback_result<'a>(
    token_resource: ResourceArc<CallbackTokenResource>,
    success: bool,
    binary_result: Binary<'a>,
) -> NifResult<rustler::Atom> {
    let mut result = token_resource.token.return_value.lock().unwrap();
    *result = Some((success, binary_result.to_vec()));
    token_resource.token.continue_signal.notify_one();

    Ok(atoms::ok())
}

// TODO: this is from wasmex... need to convert this so the result is just an optional binary
// called from elixir, params
// * callback_token
// * success: :ok | :error
//   indicates whether the call was successful or produced an elixir-error
// * results: [number]
//   return values of the elixir-callback - empty list when success-type is :error
// #[rustler::nif(name = "instance_receive_callback_result")]
// pub fn receive_callback_result(
//     token_resource: ResourceArc<CallbackTokenResource>,
//     success: bool,
//     result_list: ListIterator,
// ) -> NifResult<rustler::Atom> {
//     // let results = if success {
//     //     let return_types = token_resource.token.return_types.clone();
//     //     match decode_function_param_terms(&return_types, result_list.collect()) {
//     //         Ok(v) => v,
//     //         Err(reason) => {
//     //             return Err(Error::Term(Box::new(format!(
//     //                 "could not convert callback result param to expected return signature: {}",
//     //                 reason
//     //             ))));
//     //         }
//     //     }
//     // } else {
//     //     vec![]
//     // };

//     let mut result = token_resource.token.return_values.lock().unwrap();
//     *result = Some((success, results));
//     token_resource.token.continue_signal.notify_one();

//     Ok(atoms::ok())
// }

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
