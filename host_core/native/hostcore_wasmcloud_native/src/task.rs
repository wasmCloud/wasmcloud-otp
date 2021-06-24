use once_cell::sync::Lazy;
use tokio::runtime::Runtime;

pub(crate) static TOKIO: Lazy<Runtime> =
    Lazy::new(|| Runtime::new().expect("Wasmcloud.Native: Failed to start tokio runtime"));
