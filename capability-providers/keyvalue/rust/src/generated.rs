use serde::{Deserialize, Serialize};

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct GetArgs {
    #[serde(rename = "key")]
    pub key: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct AddArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "value")]
    pub value: i32,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "value")]
    pub value: String,
    #[serde(rename = "expires")]
    pub expires: i32,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct DelArgs {
    #[serde(rename = "key")]
    pub key: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct ClearArgs {
    #[serde(rename = "key")]
    pub key: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct RangeArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "start")]
    pub start: i32,
    #[serde(rename = "stop")]
    pub stop: i32,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct PushArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "value")]
    pub value: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct ListItemDeleteArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "value")]
    pub value: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetAddArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "value")]
    pub value: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetRemoveArgs {
    #[serde(rename = "key")]
    pub key: String,
    #[serde(rename = "value")]
    pub value: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetUnionArgs {
    #[serde(rename = "keys")]
    pub keys: Vec<String>,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetIntersectionArgs {
    #[serde(rename = "keys")]
    pub keys: Vec<String>,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetQueryArgs {
    #[serde(rename = "key")]
    pub key: String,
}

#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct KeyExistsArgs {
    #[serde(rename = "key")]
    pub key: String,
}

/// Response type for Get operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct GetResponse {
    #[serde(rename = "value")]
    pub value: String,
    #[serde(rename = "exists")]
    pub exists: bool,
}

/// Response type for Add operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct AddResponse {
    #[serde(rename = "value")]
    pub value: i32,
}

/// Response type for Delete operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct DelResponse {
    #[serde(rename = "key")]
    pub key: String,
}

/// Response type for list range operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct ListRangeResponse {
    #[serde(rename = "values")]
    pub values: Vec<String>,
}

/// Response type for list push operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct ListResponse {
    #[serde(rename = "newCount")]
    pub new_count: i32,
}

/// Response type for the Set operation, not to be confused with the set data
/// structure
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetResponse {
    #[serde(rename = "value")]
    pub value: String,
}

/// Response type for set add operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetOperationResponse {
    #[serde(rename = "new_count")]
    pub new_count: i32,
}

/// Response type for set query operations
#[derive(Debug, PartialEq, Deserialize, Serialize, Default, Clone)]
pub struct SetQueryResponse {
    #[serde(rename = "values")]
    pub values: Vec<String>,
}
