# wasmCloud Host - Web UI Dashboard
This is the web UI dashboard that provides for a basic way to interact with a host and its associated lattice. This web application automatically starts the [host_core](../host_core/README.md) application as a dependency.

## Starting the Host and Web UI Dashboard

To start the wasmCloud host and web ui, cd to this folder (wasmcloud_host), and type or paste these commands:
```
# install dependencies
mix deps.get
cd assets; npm install
# return to this folder and start the host
cd ..
mix phx.server
```
Now you can visit [`localhost:4000`](http://localhost:4000) from your browser. If you want to use a different HTTP port for the dashboard, set the environment variable PORT, for example, 

```PORT=8000 mix phx.server```

If you later update the source from github, you'll need to re-run the set of commands above.

To learn more about wasmCloud, please view the [Documentation](https://wasmcloud.dev).
