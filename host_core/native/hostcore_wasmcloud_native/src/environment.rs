use std::sync::{Condvar, Mutex};

use rustler::{
    resource::ResourceArc, types::tuple, Atom, Binary, Encoder, Env, Error, ListIterator,
    MapIterator, OwnedEnv, Term,
};

pub struct CallbackTokenResource {
    pub token: CallbackToken,
}

pub struct CallbackToken {
    pub continue_signal: Condvar,
    pub success: bool,
    pub return_value: Mutex<Option<(bool, Vec<u8>)>>,
}

pub fn on_load(env: Env) -> bool {
    rustler::resource!(CallbackTokenResource, env);
    true
}
