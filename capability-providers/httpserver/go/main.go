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
	"fmt"
	"net/http"
	"os"

	nats "github.com/nats-io/nats.go"
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
	nc.Subscribe(ldget_topic, func(m *nats.Msg) {
		fmt.Printf("Received: %s\n", string(m.Data))
	})
	nc.Subscribe(lddel_topic, func(m *nats.Msg) {
		fmt.Printf("Received: %s\n", string(m.Data))
	})
	nc.Subscribe(ldput_topic, func(m *nats.Msg) {
		fmt.Printf("Received: %s\n", string(m.Data))

		// Here we start an HTTP server based on the data (a ConfigurationValues struct that has `module` (actor), and `values` (Map<string, string>)
		http.HandleFunc("/", HelloServer)
		http.ListenAndServe(":8080", nil)
	})

}

func HelloServer(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello, %s!", r.URL.Path[1:])
}

/*
nc.Subscribe("foo", func(m *nats.Msg) {
    fmt.Printf("Received a message: %s\n", string(m.Data))
})*/
