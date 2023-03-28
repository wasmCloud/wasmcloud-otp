use anyhow::{self, bail, Context};
use async_trait::async_trait;
use log::{error, trace};
use rand::{thread_rng, Rng, RngCore};

use crate::environment::CallbackToken;
use rustler::{
    env::{OwnedEnv, SavedTerm},
    resource::ResourceArc,
    types::tuple::make_tuple,
    Binary, Encoder, Env, Error, LocalPid, NifResult, Term,
};

use std::sync::{Condvar, Mutex};
use wascap::jwt;
use wasmcloud::{
    capability, logging, numbergen, Actor, Handle, HostInvocation, LoggingInvocation,
    NumbergenInvocation, Runtime as WcRuntime,
};

use crate::{atoms, environment::CallbackTokenResource};

/// A wrapper around an instance of the wasmCloud runtime. This will be used inside a `ResourceArc` to allow
/// Elixir to maintain a long-lived reference to it
pub struct RuntimeResource {
    pub inner: WcRuntime,
}

/// A wrapper around an instance of a precompiled wasmCloud actor. This will be used inside a `ResourceArc` to allow
/// Elixir to maintain a long-lived reference to it
pub struct ActorResource {
    pub actor: Actor,
}

#[derive(NifStruct)]
#[module = "HostCore.WasmCloud.Runtime.Config"]
pub struct ExRuntimeConfig {
    host_id: String,
}

pub struct ElixirHandler {
    // Runtime pid
    pid: LocalPid,
    #[allow(unused)]
    host_id: String,
}

#[async_trait]
impl Handle<capability::Invocation> for ElixirHandler {
    async fn handle(
        &self,
        claims: &jwt::Claims<jwt::Actor>,
        binding: String,
        invocation: capability::Invocation,
        call_context: &Option<Vec<u8>>,
    ) -> anyhow::Result<Option<Vec<u8>>> {
        match invocation {
            capability::Invocation::Logging(LoggingInvocation::WriteLog { level, text }) => {
                // note: current OTP host does not have a trace log level
                let level = match level {
                    logging::Level::Debug => "debug",
                    logging::Level::Info => "info",
                    logging::Level::Warn => "warn",
                    logging::Level::Error => "error",
                };
                let callback_token = new_callback_token();

                let mut msg_env = OwnedEnv::new();
                msg_env.send_and_clear(&self.pid.clone(), |env| {
                    (
                        atoms::perform_actor_log(),
                        crate::Claims::from(claims.clone()),
                        level,
                        text,
                        callback_token.clone(),
                    )
                        .encode(env)
                });

                let mut result = callback_token.token.return_value.lock().unwrap();
                while result.is_none() {
                    result = callback_token.token.continue_signal.wait(result).unwrap();
                }

                // we don't actually care about the result from the host here

                Ok(None)
            }

            capability::Invocation::Numbergen(NumbergenInvocation::GenerateGuid) => {
                let mut buf = uuid::Bytes::default();
                thread_rng().fill_bytes(&mut buf);
                let guid = uuid::Builder::from_random_bytes(buf)
                    .into_uuid()
                    .to_string();
                trace!("generated GUID: `{guid}`");
                numbergen::serialize_response(&guid).map(Some)
            }

            capability::Invocation::Numbergen(NumbergenInvocation::RandomInRange { min, max }) => {
                let v = thread_rng().gen_range(min..=max);
                trace!("generated random u32 in range [{min};{max}]: {v}");
                numbergen::serialize_response(&v).map(Some)
            }

            capability::Invocation::Numbergen(NumbergenInvocation::Random32) => {
                let v: u32 = thread_rng().gen();
                trace!("generated random u32: {v}");
                numbergen::serialize_response(&v).map(Some)
            }

            capability::Invocation::Host(HostInvocation {
                namespace,
                operation,
                payload,
            }) => {
                let mut msg_env = OwnedEnv::new();
                let callback_token = new_callback_token();
                msg_env.send_and_clear(&self.pid.clone(), |env| {
                    (
                        atoms::invoke_callback(),
                        crate::Claims::from(claims.clone()),
                        (binding, namespace, operation),
                        payload.unwrap_or_default(),
                        call_context.clone().unwrap_or_default(),
                        callback_token.clone(),
                    )
                        .encode(env)
                });

                let mut result = callback_token.token.return_value.lock().unwrap();
                while result.is_none() {
                    result = callback_token.token.continue_signal.wait(result).unwrap();
                }
                match result
                    .as_ref()
                    .expect("expect callback token to contain a result")
                {
                    (true, payload) => Ok(Some(payload.clone())),
                    (false, e) => {
                        // TODO: verify whether we should return none here or use an Err
                        error!("Elixir callback threw an exception.");
                        bail!("Host call function failed: {e:?}")
                    }
                }
            }
        }
    }
}

// hint: make sure this is only ever called when we're going to await the condvar, otherwise we
// could "leak" condvars
fn new_callback_token() -> ResourceArc<CallbackTokenResource> {
    ResourceArc::new(CallbackTokenResource {
        token: CallbackToken {
            continue_signal: Condvar::new(),
            return_value: Mutex::new(None),
        },
    })
}

pub fn on_load(env: Env) -> bool {
    rustler::resource!(RuntimeResource, env);
    rustler::resource!(ActorResource, env);
    true
}

#[rustler::nif(name = "runtime_new")]
pub fn new(
    env: rustler::Env<'_>,
    ExRuntimeConfig { host_id }: ExRuntimeConfig,
) -> Result<ResourceArc<RuntimeResource>, rustler::Error> {
    let handler: Box<dyn Handle<capability::Invocation>> = Box::new(ElixirHandler {
        pid: env.pid(),
        host_id,
    });
    let rt = WcRuntime::new(handler)
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

/// Called from the Elixir native wrapper which is in turn wrapped by the Wasmcloud.Runtime.Server GenServer
#[rustler::nif(name = "start_actor")]
#[allow(unused_variables)]
pub fn start_actor<'a>(
    env: rustler::Env<'a>,
    runtime_resource: ResourceArc<RuntimeResource>,
    bytes: Binary<'a>,
) -> Result<ResourceArc<ActorResource>, rustler::Error> {
    let actor = Actor::new(&runtime_resource.inner, bytes.as_slice())
        .context("failed to load actor from bytes")
        .unwrap();

    let ar = ActorResource { actor };

    Ok(ResourceArc::new(ar))
}

// This does not need to be on a dirty scheduler as it simply spawns a TOKIO
// task and returns, never taking more than a millisecond
#[rustler::nif(name = "call_actor")]
pub fn call_actor<'a>(
    env: rustler::Env<'a>,
    component: ResourceArc<ActorResource>,
    operation: &str,
    payload: Binary<'a>,
    call_context: Binary<'a>,
    from: Term,
) -> rustler::Atom {
    let pid = env.pid();
    let mut thread_env = OwnedEnv::new();

    let from = thread_env.save(from);
    let payload = payload.to_vec();
    let operation = operation.to_owned();
    let call_context = call_context.to_vec();

    // ref: https://github.com/tessi/wasmex/issues/256
    // here we spawn a TOKIO task, do the work of the actor invocation,
    // and use other sync mechanisms to finish the work and send
    // the results to the caller (the `from` field)

    crate::spawn(async move {
        let response = component
            .actor
            .call_with_context(operation, Some(payload), call_context)
            .await;
        thread_env.send_and_clear(&pid, |thread_env| {
            send_actor_call_response(thread_env, from, response)
        });
    });

    // the Elixir host doesn't get this right away because it returned `:noreply`, allowing some other process
    // to reply on its behalf
    atoms::ok()
}

fn send_actor_call_response(
    thread_env: Env,
    from: SavedTerm,
    response: anyhow::Result<Result<Option<Vec<u8>>, String>>,
) -> Term {
    let from = from
        .load(thread_env)
        .decode::<Term>()
        .unwrap_or_else(|_| "could not load 'from' param".encode(thread_env));

    match response {
        Ok(opt_data) => {
            // Ultimately sends {:ok, payload} once the envelopes are removed
            let data = opt_data.unwrap_or_default();
            make_tuple(
                thread_env,
                &[
                    atoms::returned_function_call().encode(thread_env),
                    make_tuple(
                        thread_env,
                        &[atoms::ok().encode(thread_env), data.encode(thread_env)],
                    ),
                    from,
                ],
            )
        }
        Err(e) => {
            let rc = e.root_cause().to_string();
            // Once the layers are removed, sends {:error, msg}
            make_error_tuple(&thread_env, rc.as_str(), from)
        }
    }
}

/// Produces an Elixir tuple in the form {:error, reason} along with the `from` value propogated
/// through the plumbing
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

/// Part of the async plumbing. Allows the Elixir caller (NIF) to extract the result of a callback
/// operation by way of passing back a reference to the callback token
#[rustler::nif(name = "instance_receive_callback_result")]
pub fn receive_callback_result(
    token_resource: ResourceArc<CallbackTokenResource>,
    success: bool,
    binary_result: Binary<'_>,
) -> NifResult<rustler::Atom> {
    let mut result = token_resource.token.return_value.lock().unwrap();
    *result = Some((success, binary_result.to_vec()));
    token_resource.token.continue_signal.notify_one();

    Ok(atoms::ok())
}
