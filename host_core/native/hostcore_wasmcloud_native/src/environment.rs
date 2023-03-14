use std::sync::{Condvar, Mutex};

use rustler::{
    resource::ResourceArc, types::tuple, Atom, Binary, Encoder, Error, ListIterator, MapIterator,
    OwnedEnv, Term,
};

pub struct CallbackTokenResource {
    pub token: CallbackToken,
}

pub struct CallbackToken {
    pub continue_signal: Condvar,
    pub success: bool,
    pub return_value: Vec<u8>,
}
