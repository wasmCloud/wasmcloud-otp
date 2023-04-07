use std::ops::Deref;
use std::sync::{Arc, Condvar, Mutex};

use crate::{
    atoms,
    environment::{CallbackToken, CallbackTokenResource},
};

use anyhow::{self, bail, Context};
use async_trait::async_trait;
use log::{error, trace};
use rustler::{
    env::{OwnedEnv, SavedTerm},
    resource::ResourceArc,
    types::tuple::make_tuple,
    Binary, Encoder, Env, Error, LocalPid, NifResult, Term,
};
use wascap::jwt;
use wasmcloud_host::{host, logging, Actor, Runtime as WcRuntime};

/// A wrapper around an instance of the wasmCloud runtime. This will be used inside a `ResourceArc` to allow
/// Elixir to maintain a long-lived reference to it
pub struct RuntimeResource {
    inner: WcRuntime,
    /// Runtime process ID
    pid: LocalPid,
}

/// A wrapper around an instance of a precompiled wasmCloud actor. This will be used inside a `ResourceArc` to allow
/// Elixir to maintain a long-lived reference to it
#[derive(Clone)]
pub struct ActorResource {
    inner: Actor,
    runtime_pid: LocalPid,
}

impl Deref for ActorResource {
    type Target = Actor;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}

#[derive(NifStruct)]
#[module = "HostCore.WasmCloud.Runtime.Config"]
pub struct ExRuntimeConfig {
    host_id: String,
}

#[derive(Clone)]
pub struct ElixirHandler {
    /// Runtime process ID
    pid: LocalPid,
    claims: jwt::Claims<jwt::Actor>,
    call_context: Vec<u8>,
}

#[derive(Clone)]
struct ElixirHandlerArc(Arc<ElixirHandler>);

impl Deref for ElixirHandlerArc {
    type Target = ElixirHandler;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl From<ElixirHandler> for ElixirHandlerArc {
    fn from(handler: ElixirHandler) -> Self {
        Self(handler.into())
    }
}

#[async_trait]
impl logging::Host for ElixirHandlerArc {
    async fn log(
        &mut self,
        level: logging::Level,
        _context: String,
        message: String,
    ) -> anyhow::Result<()> {
        // note: current OTP host does not have a trace log level
        let level = match level {
            logging::Level::Trace => {
                trace!("drop `trace` level log");
                return Ok(());
            }
            logging::Level::Debug => "debug",
            logging::Level::Info => "info",
            logging::Level::Warn => "warn",
            logging::Level::Error => "error",
            logging::Level::Critical => "error", // TODO: Implement this level in OTP
        };
        let callback_token = new_callback_token();

        let mut msg_env = OwnedEnv::new();
        msg_env.send_and_clear(&self.pid, |env| {
            (
                atoms::perform_actor_log(),
                crate::Claims::from(self.claims.clone()),
                level,
                message,
                &callback_token,
            )
                .encode(env)
        });

        let mut result = callback_token.token.return_value.lock().unwrap();
        while result.is_none() {
            result = callback_token.token.continue_signal.wait(result).unwrap();
        }

        Ok(())
    }
}

#[async_trait]
impl host::Host for ElixirHandlerArc {
    async fn call(
        &mut self,
        binding: String,
        namespace: String,
        operation: String,
        payload: Option<Vec<u8>>,
    ) -> anyhow::Result<Result<Option<Vec<u8>>, String>> {
        let mut msg_env = OwnedEnv::new();
        let callback_token = new_callback_token();
        msg_env.send_and_clear(&self.pid, |env| {
            (
                atoms::invoke_callback(),
                crate::Claims::from(self.claims.clone()),
                (binding, namespace, operation),
                &payload,
                &self.call_context,
                &callback_token,
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
            (true, payload) => Ok(Ok(Some(payload.clone()))),
            (false, e) => {
                // TODO: verify whether we should return none here or use an Err
                error!("Elixir callback threw an exception.");
                bail!("Host call function failed: {e:?}")
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
    _config: ExRuntimeConfig,
) -> Result<ResourceArc<RuntimeResource>, rustler::Error> {
    let inner = WcRuntime::new()
        .context("failed to construct runtime")
        .map_err(|e| Error::Term(Box::new(e.to_string())))?;
    Ok(ResourceArc::new(RuntimeResource {
        inner,
        pid: env.pid(),
    }))
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
    runtime: ResourceArc<RuntimeResource>,
    bytes: Binary<'a>,
) -> Result<ResourceArc<ActorResource>, rustler::Error> {
    let inner = Actor::new(&runtime.inner, bytes.as_slice())
        .context("failed to load actor from bytes")
        .unwrap();
    Ok(ResourceArc::new(ActorResource {
        inner,
        runtime_pid: runtime.pid,
    }))
}

// This does not need to be on a dirty scheduler as it simply spawns a TOKIO
// task and returns, never taking more than a millisecond
#[rustler::nif(name = "call_actor")]
pub fn call_actor<'a>(
    env: rustler::Env<'a>,
    actor: ResourceArc<ActorResource>,
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

    let runtime_pid = actor.runtime_pid;
    let (actor, claims) = actor.inner.clone().into_configure_claims();
    let handler = ElixirHandlerArc::from(ElixirHandler {
        pid: runtime_pid,
        claims,
        call_context,
    });
    let actor = actor.logging(handler.clone()).host(handler);
    crate::spawn(async move {
        let response = actor.call(operation, Some(payload)).await;
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
