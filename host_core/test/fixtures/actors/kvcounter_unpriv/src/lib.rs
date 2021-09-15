use serde_json::json;
use wasmbus_rpc::actor::prelude::*;
use wasmcloud_interface_httpserver::{HttpRequest, HttpResponse, HttpServer, HttpServerReceiver};
use wasmcloud_interface_keyvalue::{IncrementRequest, KeyValue, KeyValueSender};

#[derive(Debug, Default, Actor, HealthResponder)]
#[services(Actor, HttpServer)]
struct KvCounterActor {}

/// Implementation of HttpServer trait methods
#[async_trait]
impl HttpServer for KvCounterActor {
    async fn handle_request(&self, ctx: &Context, req: &HttpRequest) -> RpcResult<HttpResponse> {
        // make friendlier key
        let key = format!("counter:{}", req.path.replace('/', ":"));

        // bonus: use specified amount from query, or 1
        let amount: i32 = form_urlencoded::parse(req.query_string.as_bytes())
            .find(|(n, _)| n == "amount")
            .map(|(_, v)| v.parse::<i32>())
            .unwrap_or(Ok(1))
            .unwrap_or(1);

        // increment the value in kv and send response in json
        let (body, status_code) = match increment_counter(ctx, key, amount).await {
            Ok(v) => (json!({ "counter": v }).to_string(), 200),
            // if we caught an error, return it to client
            Err(e) => (json!({ "error": e.to_string() }).to_string(), 500),
        };
        let resp = HttpResponse {
            body: body.as_bytes().to_vec(),
            status_code,
            ..Default::default()
        };
        Ok(resp)
    }
}

/// increment the counter by the amount, returning the new value
async fn increment_counter(ctx: &Context, key: String, value: i32) -> RpcResult<i32> {
    let new_val = KeyValueSender::new()
        .increment(ctx, &IncrementRequest { key, value })
        .await?;
    Ok(new_val)
}
