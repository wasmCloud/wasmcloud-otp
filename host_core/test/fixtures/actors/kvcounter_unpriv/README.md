# KVCounter Unpriviledged

This is a modification of the original kvcounter example actor that does not have the `wasmcloud:keyvalue` capability claim. It can be built for testing purposes and found in `./build/kvcounter_s.wasm` after running `make`. Signing keys are included in this project to ensure keys can be asserted in tests as well

## Original README 

This actor accepts http GET requests, and 
increments a counter whose name is based on the url path.
Each unique url is associated a unique counter.
The result is returned in a JSON payload as follows:

```json
{
    "counter": 12
}
```

This actor makes use of the HTTP server (`wasmcloud:httpserver`) capability 
and the key-value store capability (`wasmcloud:keyvalue`). 

As usual, it is worth noting that this actor does _not_ know 
where its HTTP server comes from, nor does it know which 
key-value implementation the host runtime has provided.
