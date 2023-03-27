rustler::atoms! {
    ok,
    error,

    /// Server key type
    server,
    /// Cluster key type
    cluster,
    /// Operator key type
    operator,
    /// Account key type
    account,
    /// User key type
    user,
    /// Module key type (actor)
    module,
    /// Service provider key type
    provider,
    //atom __true__ = "true";
    //atom __false__ = "false";

    // calls to erlang processes
    returned_function_call,
    invoke_callback,

    perform_actor_log,
}
