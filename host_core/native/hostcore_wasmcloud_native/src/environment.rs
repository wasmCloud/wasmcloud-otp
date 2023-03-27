use std::sync::{Condvar, Mutex};

use rustler::Env;

pub struct CallbackTokenResource {
    pub token: CallbackToken,
}

pub struct CallbackToken {
    pub continue_signal: Condvar,
    /// Holds the return data from the call, (success, payload) in an Option in a mutex
    pub return_value: Mutex<Option<(bool, Vec<u8>)>>,
}

pub fn on_load(env: Env) -> bool {
    rustler::resource!(CallbackTokenResource, env);
    true
}
