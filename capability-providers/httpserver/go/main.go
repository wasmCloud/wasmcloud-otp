package main

/*
  Topics relevant to a capability provider:

 RPC:
    * wasmbus.rpc.default.{provider_key}.{link_name} - Get Invocation, answer InvocationResponse`wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.put` - Publish link definition (e.g. bind to an actor)
    * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.get - Query all link defss for this provider. (queue subscribed)
    * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.del - Remove a link def. Provider de-provisions resources for the given actor.
    * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.put - Puts a link def. Provider provisions resources for the given actor.

    Linkdef operations must always be idempotent and are not queue subscribed.
*/

import (
	"context"
	"fmt"
	"net/http"
	"os"

	nats "github.com/nats-io/nats.go"
	msgpack "github.com/vmihailenco/msgpack/v5"
)

type LinkDefinition struct {
	ActorID    string            `msgpack:"actor_id"`
	ProviderID string            `msgpack:"provider_id"`
	LinkName   string            `msgpack:"link_name"`
	ContractID string            `msgpack:"contract_id"`
	Values     map[string]string `msgpack:"values"`
}

type Invocation struct {
}

/*
pub struct Invocation {
   ??? pub origin: WasmCloudEntity,
   ??? pub target: WasmCloudEntity,
    pub operation: String,
    pub msg: Vec<u8>,
    pub id: String,
    pub encoded_claims: String,
    pub host_id: String,
}*/

var (
	serverCancels map[string]context.CancelFunc
)

func main() {
	lattice_prefix := os.Getenv("LATTICE_RPC_PREFIX")
	provider_key := os.Getenv("PROVIDER_KEY")
	link_name := os.Getenv("PROVIDER_LINK_NAME")

	nc, _ := nats.Connect(nats.DefaultURL)

	rpc_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s", lattice_prefix, provider_key, link_name)
	ldget_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.get", lattice_prefix, provider_key, link_name)
	lddel_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.del", lattice_prefix, provider_key, link_name)
	ldput_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.put", lattice_prefix, provider_key, link_name)

	nc.Subscribe(rpc_topic, func(m *nats.Msg) {
		fmt.Printf("Received: %s\n", string(m.Data))
	})
	nc.QueueSubscribe(ldget_topic, ldget_topic, func(m *nats.Msg) {
		fmt.Printf("Received: %s\n", string(m.Data))
	})
	nc.Subscribe(lddel_topic, func(m *nats.Msg) {
		fmt.Printf("Received: %s\n", string(m.Data))

		// Trigger the cancel context for the server
		serverCancels["Mxxxx"]()
	})

	nc.Subscribe(ldput_topic, func(m *nats.Msg) {
		var linkdef LinkDefinition
		err := msgpack.Unmarshal(m.Data, &linkdef)
		if err != nil {
			fmt.Printf("Failed to unpack msgpack: %s\n", err)
			return
		}
		fmt.Println("Received link definition PUT")

		ctx, closeServer := context.WithCancel(context.Background())
		serverCancels["Mxxxx"] = closeServer

		srv := createHttpServer(8080) // TODO: get port from link def
		go func() {
			<-ctx.Done()
			fmt.Println("Shutting down HTTP server for Mxxxxx")
			srv.Shutdown(ctx)
		}()

		go func() {
			http.HandleFunc("/", handleRequest)
			fmt.Printf("Listening for requests...\n")
			srv.ListenAndServe()
		}()
	})

}

func createHttpServer(port int) *http.Server {
	fmt.Printf("Creating HTTP server on port %d", port)
	srv := &http.Server{Addr: fmt.Sprintf(":%d", port)}

	return srv
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	// 1. create an invocation out of the incoming request (invocation wrapping Request type)
	// 2. send to core via NATS request
	// 3. convert InvocationResponse to http response
	fmt.Fprintf(w, "Hello, %s!", r.URL.Path[1:])
}

// this is here just to remind us how to use msgpack.
func ExampleMarshal() {
	type Item struct {
		Foo string
	}

	b, err := msgpack.Marshal(&Item{Foo: "bar"})
	if err != nil {
		panic(err)
	}

	var item Item
	err = msgpack.Unmarshal(b, &item)
	if err != nil {
		panic(err)
	}
	fmt.Println(item.Foo)
	// Output: bar
}
