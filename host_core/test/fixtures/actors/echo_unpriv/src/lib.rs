use serde_json::json;
use wasmbus_rpc::actor::prelude::*;
use wasmcloud_interface_httpserver::{HttpRequest, HttpResponse, HttpServer, HttpServerReceiver};

#[derive(Debug, Default, Actor, HealthResponder)]
#[services(Actor, HttpServer)]
struct EchoActor {}

/// Implementation of HttpServer trait methods
#[async_trait]
impl HttpServer for EchoActor {
    async fn handle_request(&self, _ctx: &Context, value: &HttpRequest) -> RpcResult<HttpResponse> {
        let body = json!({
            "method": &value.method,
            "path": &value.path,
            "query_string": &value.query_string,
            "body": &value.body,
        });
        let resp = HttpResponse {
            body: serde_json::to_vec(&body)
                .map_err(|e| RpcError::ActorHandler(format!("serializing response: {}", e)))?,
            ..Default::default()
        };
        Ok(resp)
    }
}
