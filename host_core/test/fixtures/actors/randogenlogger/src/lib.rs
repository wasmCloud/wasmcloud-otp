use wasmbus_rpc::actor::prelude::*;
use wasmcloud_interface_httpserver::{HttpRequest, HttpResponse, HttpServer, HttpServerReceiver};
use wasmcloud_interface_logging::{debug, error, info, warn, LogEntry, Logging, LoggingSender};
use wasmcloud_interface_numbergen::{generate_guid, random_32, random_in_range};

#[derive(Debug, Default, Actor, HealthResponder)]
#[services(Actor, HttpServer)]
struct RandogenloggerActor {}

/// Implementation of HttpServer trait methods
#[async_trait]
impl HttpServer for RandogenloggerActor {
    /// Returns a greeting, "Hello World", in the response body.
    /// If the request contains a query parameter 'name=NAME', the
    /// response is changed to "Hello NAME"
    async fn handle_request(
        &self,
        ctx: &Context,
        _req: &HttpRequest,
    ) -> std::result::Result<HttpResponse, RpcError> {
        debug!("a debug!");
        info!("an info!");
        warn!("a warn!");
        error!("an error!");
        LoggingSender::new()
            .write_log(
                ctx,
                &LogEntry {
                    level: "info".to_string(),
                    text: "a manual info!".to_string(),
                },
            )
            .await?;

        generate_guid().await?;
        random_32().await?;
        random_in_range(0, 100).await?;
        Ok(HttpResponse {
            body: "I did it".to_string().as_bytes().to_vec(),
            ..Default::default()
        })
    }
}
