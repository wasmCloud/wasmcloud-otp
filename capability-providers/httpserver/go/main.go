package main

/*
  Topics relevant to a capability provider:

 RPC:
    * wasmbus.rpc.default.{provider_key}.{link_name} - Get Invocation, answer InvocationResponse
    * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.get - Query all link defs for this provider. (queue subscribed)
    * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.del - Remove a link def. Provider de-provisions resources for the given actor.
    * wasmbus.rpc.{prefix}.{public_key}.{link_name}.linkdefs.put - Puts a link def. Provider provisions resources for the given actor.

    Linkdef operations must always be idempotent and are not queue subscribed.
*/

import (
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strconv"
	"sync"

	nats "github.com/nats-io/nats.go"
	msgpack "github.com/vmihailenco/msgpack/v5"
)

//TODO: Change to msgpack
type LinkDefinition struct {
	ActorID    string            `json:"actor_id"`
	ProviderID string            `json:"provider_id"`
	LinkName   string            `json:"link_name"`
	ContractID string            `json:"contract_id"`
	Values     map[string]string `json:"values"`
}

type WasmCloudEntity struct {
	PublicKey  string `msgpack:"public_key"`
	LinkName   string `msgpack:"link_name"`
	ContractID string `msgpack:"contract_id"`
}

type Invocation struct {
	Origin        WasmCloudEntity `msgpack:"origin"`
	Target        WasmCloudEntity `msgpack:"target"`
	Operation     string          `msgpack:"operation"`
	Msg           []byte          `msgpack:"msg"`
	ID            string          `msgpack:"id"`
	EncodedClaims string          `msgpack:"encoded_claims"`
	HostID        string          `msgpack:"host_id"`
}

// HTTP Request object
type Request struct {
	Method      string            `msgpack:"method"`
	Path        string            `msgpack:"path"`
	QueryString string            `msgpack:"queryString"`
	Header      map[string]string `msgpack:"header"`
	Body        []byte            `msgpack:"body"`
}

// HTTP Response object
type Response struct {
	StatusCode uint32            `msgpack:"statusCode"`
	Status     string            `msgpack:"status"`
	Header     map[string]string `msgpack:"header"`
	Body       []byte            `msgpack:"body"`
}

var (
	serverCancels map[string]context.CancelFunc
	linkDefs      map[string]LinkDefinition
)

func main() {
	lattice_prefix := os.Getenv("LATTICE_RPC_PREFIX")
	provider_key := os.Getenv("PROVIDER_KEY")
	link_name := os.Getenv("PROVIDER_LINK_NAME")

	serverCancels := make(map[string]context.CancelFunc)
	linkDefs := make(map[string]LinkDefinition)
	nc, _ := nats.Connect(nats.DefaultURL)
	http.HandleFunc("/", handleRequest)

	ldget_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.get", lattice_prefix, provider_key, link_name)
	lddel_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.del", lattice_prefix, provider_key, link_name)
	ldput_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.put", lattice_prefix, provider_key, link_name)
	shutdown_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.shutdown", lattice_prefix, provider_key, link_name)

	nc.QueueSubscribe(ldget_topic, ldget_topic, func(m *nats.Msg) {
		msg, err := json.Marshal(linkDefs)
		if err != nil {
			fmt.Printf("Failed to pack json: %s\n", err)
		}
		nc.Publish(m.Reply, msg)
	})

	nc.Subscribe(lddel_topic, func(m *nats.Msg) {
		var linkdef LinkDefinition
		err := json.Unmarshal(m.Data, &linkdef)
		if err != nil {
			fmt.Printf("Failed to unpack json: %s\n", err)
			return
		}

		// Trigger the cancel context for the server
		if cancel := serverCancels[linkdef.ActorID]; cancel != nil {
			delete(serverCancels, linkdef.ActorID)
			delete(linkDefs, linkdef.ActorID)
			cancel()
		} else {
			fmt.Printf("HTTP server not running for actor: %s\n", linkdef.ActorID)
		}
	})

	nc.Subscribe(ldput_topic, func(m *nats.Msg) {
		var linkdef LinkDefinition
		err := json.Unmarshal(m.Data, &linkdef)
		if err != nil {
			fmt.Printf("Failed to unpack json: %s\n", err)
			return
		}

		port, err := strconv.Atoi(linkdef.Values["PORT"])
		if err != nil {
			fmt.Printf("Error starting HTTP server, no PORT supplied: %s\n", err)
			return
		}

		if serverCancels[linkdef.ActorID] != nil {
			fmt.Printf("HTTP server already exists for actor: %s\n", linkdef.ActorID)
			return
		}

		ctx, closeServer := context.WithCancel(context.Background())
		serverCancels[linkdef.ActorID] = closeServer
		linkDefs[linkdef.ActorID] = linkdef

		srv := createHttpServer(linkdef.ActorID, port)
		go func() {
			<-ctx.Done()
			fmt.Printf("Shutting down HTTP server for: %s\n", linkdef.ActorID)
			srv.Shutdown(ctx)
		}()

		go func() {
			fmt.Printf("Listening for requests...\n")
			srv.ListenAndServe()
		}()
	})

	wg := sync.WaitGroup{}
	wg.Add(1)
	nc.Subscribe(shutdown_topic, func(m *nats.Msg) {
		fmt.Println("Received shutdown signal, shutting down")
		wg.Done()
	})
	fmt.Println("HTTP Server ready for link definitions")
	wg.Wait()
}

func createHttpServer(actorID string, port int) *http.Server {
	fmt.Printf("Creating HTTP server on port %d\n", port)
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handleActorRequest(actorID, w, r)
	})
	srv := &http.Server{Addr: fmt.Sprintf(":%d", port), Handler: handler}

	return srv
}

func handleActorRequest(actorID string, w http.ResponseWriter, r *http.Request) {
	origin := WasmCloudEntity{ //TODO: get these values from provider info
		PublicKey:  "VASD",
		LinkName:   "default",
		ContractID: "wasmcloud:httpserver",
	}
	target := WasmCloudEntity{
		PublicKey: actorID,
	}
	msg, err := ioutil.ReadAll(r.Body)
	if err != nil {
		fmt.Println("Failed to read HTTP request body")
	}
	invocation := Invocation{
		Origin:        origin,
		Target:        target,
		Operation:     "HandleRequest",
		Msg:           msg,
		ID:            "",
		EncodedClaims: "",
		HostID:        "",
	}
	// 2. send to core via NATS request
	// 3. convert InvocationResponse to http response
	fmt.Printf("HANDLER INVOKED: %s\n", invocation)
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello, %s!", r.URL)
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
