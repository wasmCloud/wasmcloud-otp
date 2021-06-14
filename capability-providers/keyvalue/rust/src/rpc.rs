use crate::deserialize;
use crate::{Invocation, InvocationResponse};
use redis::Connection;
use redis::{self, Commands};
use std::error::Error;

const OP_ADD: &str = "Add";
const OP_GET: &str = "Get";
const OP_SET: &str = "Set";
const OP_DEL: &str = "Del";
const OP_CLEAR: &str = "Clear";
const OP_RANGE: &str = "Range";
const OP_PUSH: &str = "Push";
const OP_LIST_DEL: &str = "ListItemDelete";
const OP_SET_ADD: &str = "SetAdd";
const OP_SET_REMOVE: &str = "SetRemove";
const OP_SET_UNION: &str = "SetUnion";
const OP_SET_INTERSECT: &str = "SetIntersection";
const OP_SET_QUERY: &str = "SetQuery";
const OP_KEY_EXISTS: &str = "KeyExists";

use crate::generated::*;

type OpResult = Result<InvocationResponse, Box<dyn Error + Send + Sync>>;

pub(crate) fn handle_rpc(inv: Invocation) -> InvocationResponse {
    // We can assume all origins of calls coming to this provider
    // are from actors
    match dispatch_operation(&inv.id, &inv.operation, &inv.origin.public_key, &inv.msg) {
        Ok(v) => v,
        Err(e) => InvocationResponse::failure(&inv, &format!("{}", e)),
    }
}

fn dispatch_operation(inv_id: &str, op: &str, actor: &str, bytes: &[u8]) -> OpResult {
    let mut conn = actor_con(actor)?;
    let inv = match op {
        OP_ADD => add(&mut conn, deserialize(bytes)?),
        OP_DEL => del(&mut conn, deserialize(bytes)?),
        OP_GET => get(&mut conn, deserialize(bytes)?),
        OP_SET => set(&mut conn, deserialize(bytes)?),
        OP_CLEAR => clear(&mut conn, deserialize(bytes)?),
        OP_RANGE => list_range(&mut conn, deserialize(bytes)?),
        OP_PUSH => list_push(&mut conn, deserialize(bytes)?),
        OP_LIST_DEL => list_del(&mut conn, deserialize(bytes)?),
        OP_SET_ADD => set_add(&mut conn, deserialize(bytes)?),
        OP_SET_REMOVE => set_remove(&mut conn, deserialize(bytes)?),
        OP_SET_UNION => set_union(&mut conn, deserialize(bytes)?),
        OP_SET_INTERSECT => set_intersect(&mut conn, deserialize(bytes)?),
        OP_SET_QUERY => set_query(&mut conn, deserialize(bytes)?),
        OP_KEY_EXISTS => key_exists(&mut conn, deserialize(bytes)?),
        _ => Err("No such operation".into()),
    }?;
    Ok(InvocationResponse {
        invocation_id: inv_id.to_string(),
        ..inv
    })
}

fn add(conn: &mut Connection, args: AddArgs) -> OpResult {
    let res: i32 = conn.incr(args.key, args.value)?;
    Ok(InvocationResponse::success(AddResponse { value: res }))
}

fn del(conn: &mut Connection, args: DelArgs) -> OpResult {
    conn.del(&args.key)?;
    Ok(InvocationResponse::success(DelResponse { key: args.key }))
}

fn set(conn: &mut Connection, args: SetArgs) -> OpResult {
    conn.set(&args.key, &args.value)?;
    Ok(InvocationResponse::success(SetResponse {
        value: args.value.clone(),
    }))
}

fn get(conn: &mut Connection, args: GetArgs) -> OpResult {
    if !conn.exists(&args.key)? {
        Ok(InvocationResponse::success(GetResponse {
            value: String::from(""),
            exists: false,
        }))
    } else {
        let v: redis::RedisResult<String> = conn.get(&args.key);
        Ok(InvocationResponse::success(match v {
            Ok(s) => GetResponse {
                value: s,
                exists: true,
            },
            Err(e) => {
                error!("GET for {} failed: {}", &args.key, e);
                GetResponse {
                    value: "".to_string(),
                    exists: false,
                }
            }
        }))
    }
}

fn clear(conn: &mut Connection, args: ClearArgs) -> OpResult {
    del(
        conn,
        DelArgs {
            key: args.key.clone(),
        },
    ) // clearing a list is the same as deleting its key
}

fn list_range(conn: &mut Connection, args: RangeArgs) -> OpResult {
    let result: Vec<String> = conn.lrange(args.key, args.start as _, args.stop as _)?;
    Ok(InvocationResponse::success(ListRangeResponse {
        values: result,
    }))
}

fn list_push(conn: &mut Connection, args: PushArgs) -> OpResult {
    let result: i32 = conn.lpush(args.key, args.value)?;
    Ok(InvocationResponse::success(ListResponse {
        new_count: result,
    }))
}

fn list_del(conn: &mut Connection, args: PushArgs) -> OpResult {
    let result: i32 = conn.lrem(args.key, 0, &args.value)?;
    Ok(InvocationResponse::success(ListResponse {
        new_count: result,
    }))
}

fn set_add(conn: &mut Connection, args: SetAddArgs) -> OpResult {
    let result = conn.sadd(args.key, &args.value)?;
    Ok(InvocationResponse::success(SetOperationResponse {
        new_count: result,
    }))
}

fn set_remove(conn: &mut Connection, args: SetRemoveArgs) -> OpResult {
    let result = conn.srem(args.key, &args.value)?;
    Ok(InvocationResponse::success(SetOperationResponse {
        new_count: result,
    }))
}

fn set_union(conn: &mut Connection, args: SetUnionArgs) -> OpResult {
    let result: Vec<String> = conn.sunion(args.keys)?;
    Ok(InvocationResponse::success(SetQueryResponse {
        values: result,
    }))
}

fn set_intersect(conn: &mut Connection, args: SetUnionArgs) -> OpResult {
    let result: Vec<String> = conn.sunion(args.keys)?;
    Ok(InvocationResponse::success(SetQueryResponse {
        values: result,
    }))
}

fn set_query(conn: &mut Connection, args: SetQueryArgs) -> OpResult {
    let result: Vec<String> = conn.smembers(args.key)?;
    Ok(InvocationResponse::success(SetQueryResponse {
        values: result,
    }))
}

fn key_exists(conn: &mut Connection, args: KeyExistsArgs) -> OpResult {
    let result: bool = conn.exists(args.key)?;
    Ok(InvocationResponse::success(GetResponse {
        value: "".to_string(),
        exists: result,
    }))
}

fn actor_con(actor: &str) -> Result<Connection, Box<dyn Error + Send + Sync>> {
    let lock = crate::CLIENTS.read().unwrap();
    if let Some(client) = lock.get(actor) {
        client.get_connection().map_err(|e| format!("{}", e).into())
    } else {
        Err("No client for this actor. Did the host configure it?".into())
    }
}
