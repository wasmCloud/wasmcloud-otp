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
	"fmt"
	"io/ioutil"
	"net/http"
	"strconv"
	"sync"
	"time"

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

type InvocationResponse struct {
	InvocationID string `msgpack:"invocation_id"`
	Msg          []byte `msgpack:"msg"`
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
	//TODO: source these values from host configuration of provider
	// lattice_prefix := os.Getenv("LATTICE_RPC_PREFIX")
	// provider_key := os.Getenv("PROVIDER_KEY")
	// link_name := os.Getenv("PROVIDER_LINK_NAME")
	lattice_prefix := "default"
	provider_key := "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M"
	link_name := "default"

	serverCancels := make(map[string]context.CancelFunc)
	linkDefs := make(map[string]LinkDefinition)
	nc, _ := nats.Connect(nats.DefaultURL)
	http.HandleFunc("/", handleRequest)

	ldget_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.get", lattice_prefix, provider_key, link_name)
	lddel_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.del", lattice_prefix, provider_key, link_name)
	ldput_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.linkdefs.put", lattice_prefix, provider_key, link_name)
	shutdown_topic := fmt.Sprintf("wasmbus.rpc.%s.%s.%s.shutdown", lattice_prefix, provider_key, link_name)

	nc.QueueSubscribe(ldget_topic, ldget_topic, func(m *nats.Msg) {
		msg, err := msgpack.Marshal(linkDefs)
		if err != nil {
			fmt.Printf("Failed to pack msgpack: %s\n", err)
		}
		nc.Publish(m.Reply, msg)
	})

	nc.Subscribe(lddel_topic, func(m *nats.Msg) {
		var linkdef LinkDefinition
		err := msgpack.Unmarshal(m.Data, &linkdef)
		if err != nil {
			fmt.Printf("Failed to unpack msgpack: %s\n", err)
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
		err := msgpack.Unmarshal(m.Data, &linkdef)
		if err != nil {
			fmt.Printf("Failed to unpack msgpack: %s\n", err)
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

		srv := createHttpServer(linkdef.ActorID, nc, port)
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

func createHttpServer(actorID string, nc *nats.Conn, port int) *http.Server {
	fmt.Printf("Creating HTTP server on port %d\n", port)
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handleActorRequest(actorID, nc, w, r)
	})
	srv := &http.Server{Addr: fmt.Sprintf(":%d", port), Handler: handler}

	return srv
}

func handleActorRequest(actorID string, nc *nats.Conn, w http.ResponseWriter, r *http.Request) {
	origin := WasmCloudEntity{ //TODO: get these values from provider info
		PublicKey:  "VAG3QITQQ2ODAOWB5TTQSDJ53XK3SHBEIFNK4AYJ5RKAX2UNSCAPHA5M",
		LinkName:   "default",
		ContractID: "wasmcloud:httpserver",
	}
	target := WasmCloudEntity{
		PublicKey: actorID,
	}

	reqBody, err := ioutil.ReadAll(r.Body)
	if err != nil {
		fmt.Println("Failed to read HTTP request body")
	}
	httpReq := Request{
		Method:      r.Method,
		Path:        r.URL.Path,
		QueryString: r.URL.RawQuery,
		Body:        reqBody,
		Header:      make(map[string]string),
	}
	msg, err := msgpack.Marshal(httpReq)
	if err != nil {
		fmt.Printf("Failed to marshal msgpack: %s\n", err)
		return
	}
	//TODO: generate guid, source values from provider info
	invocation := Invocation{
		Origin:        origin,
		Target:        target,
		Operation:     "HandleRequest",
		Msg:           msg,
		ID:            "todo:guid",
		EncodedClaims: "todo:jwt",
		HostID:        "Nidkman",
	}

	subj := fmt.Sprintf("wasmbus.rpc.default.%s", actorID)
	natsBody, err := msgpack.Marshal(invocation)
	if err != nil {
		fmt.Printf("Failed to marshal msgpack: %s\n", err)
		return
	}
	resp, err := nc.Request(subj, natsBody, 2*time.Second)
	if err != nil {
		fmt.Printf("RPC Failure: %s\n", err)
		return
	}
	var invResp InvocationResponse
	err = msgpack.Unmarshal(resp.Data, &invResp)
	if err != nil {
		fmt.Printf("Failed to unpack invocation msgpack: %s\n", err)
		return
	}
	var httpResponse Response
	err = msgpack.Unmarshal(invResp.Msg, &httpResponse)
	if err != nil {
		fmt.Printf("Failed to unpack response msgpack: %s\n", err)
		return
	}
	w.Write(httpResponse.Body)
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
