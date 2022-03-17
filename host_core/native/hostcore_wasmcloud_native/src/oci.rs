use std::collections::HashMap;
use std::env::{temp_dir, var};
use std::path::PathBuf;
use std::str::FromStr;
use tokio::io::AsyncWriteExt;

use oci_distribution::secrets::RegistryAuth;

pub(crate) const OCI_VAR_USER: &str = "OCI_REGISTRY_USER";
pub(crate) const OCI_VAR_PASSWORD: &str = "OCI_REGISTRY_PASSWORD";
const PROVIDER_ARCHIVE_MEDIA_TYPE: &str = "application/vnd.wasmcloud.provider.archive.layer.v1+par";
const WASM_MEDIA_TYPE: &str = "application/vnd.module.wasm.content.layer.v1+wasm";
const OCI_MEDIA_TYPE: &str = "application/vnd.oci.image.layer.v1.tar";

fn determine_auth(creds_override: Option<HashMap<String, String>>) -> RegistryAuth {
    if let Some(hm) = creds_override {
        match (hm.get("username"), hm.get("password")) {
            (Some(un), Some(pw)) => {
                oci_distribution::secrets::RegistryAuth::Basic(un.to_string(), pw.to_string())
            }
            _ => oci_distribution::secrets::RegistryAuth::Anonymous,
        }
    } else {
        match (var(OCI_VAR_USER), var(OCI_VAR_PASSWORD)) {
            (Ok(u), Ok(p)) => oci_distribution::secrets::RegistryAuth::Basic(u, p),
            _ => oci_distribution::secrets::RegistryAuth::Anonymous,
        }
    }
}

pub(crate) async fn fetch_oci_path(
    img: &str,
    allow_latest: bool,
    allowed_insecure: Vec<String>,
    creds_override: Option<HashMap<String, String>>,
) -> Result<PathBuf, Box<dyn std::error::Error + Sync + Send>> {
    if !allow_latest && img.ends_with(":latest") {
        return Err(
            "Fetching images tagged 'latest' is currently prohibited in this host. This option can be overridden".into());
    }
    let cf = cached_file(img).await?;
    if tokio::fs::metadata(&cf).await.is_err() {
        let img = oci_distribution::Reference::from_str(img)?;
        let auth = determine_auth(creds_override);

        let protocol =
            oci_distribution::client::ClientProtocol::HttpsExcept(allowed_insecure.to_vec());
        let config = oci_distribution::client::ClientConfig {
            protocol,
            ..Default::default()
        };
        let mut c = oci_distribution::Client::new(config);
        let imgdata = pull(&mut c, &img, &auth).await;

        match imgdata {
            Ok(imgdata) => {
                let mut f = tokio::fs::File::create(&cf).await?;
                let content = imgdata
                    .layers
                    .into_iter()
                    .flat_map(|l| l.data)
                    .collect::<Vec<_>>();
                f.write_all(&content).await?;
                f.flush().await?;
            }
            Err(e) => return Err(format!("Failed to fetch OCI bytes: {}", e).into()),
        }
    }

    Ok(cf)
}

async fn cached_file(img: &str) -> std::io::Result<PathBuf> {
    let path = temp_dir();
    let path = path.join("wasmcloud_ocicache");
    ::tokio::fs::create_dir_all(&path).await?;
    // should produce a file like wasmcloud_azurecr_io_kvcounter_v1.bin
    let img = img.replace(':', "_");
    let img = img.replace('/', "_");
    let img = img.replace('.', "_");
    let mut path = path.join(img);
    path.set_extension("bin");

    Ok(path)
}

async fn pull(
    client: &mut oci_distribution::Client,
    img: &oci_distribution::Reference,
    auth: &oci_distribution::secrets::RegistryAuth,
) -> ::std::result::Result<
    oci_distribution::client::ImageData,
    Box<dyn std::error::Error + Sync + Send>,
> {
    client
        .pull(
            img,
            auth,
            vec![PROVIDER_ARCHIVE_MEDIA_TYPE, WASM_MEDIA_TYPE, OCI_MEDIA_TYPE],
        )
        .await
        .map_err(|e| format!("{}", e).into())
}
