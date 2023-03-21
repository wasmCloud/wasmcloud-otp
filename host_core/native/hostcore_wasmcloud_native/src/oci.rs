use oci_distribution::secrets::RegistryAuth;
use std::collections::HashMap;
use std::env::{temp_dir, var};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use tokio::io::AsyncWriteExt;

pub(crate) const OCI_VAR_REGISTRY: &str = "OCI_REGISTRY";
pub(crate) const OCI_VAR_USER: &str = "OCI_REGISTRY_USER";
pub(crate) const OCI_VAR_PASSWORD: &str = "OCI_REGISTRY_PASSWORD";
const PROVIDER_ARCHIVE_MEDIA_TYPE: &str = "application/vnd.wasmcloud.provider.archive.layer.v1+par";
const WASM_MEDIA_TYPE: &str = "application/vnd.module.wasm.content.layer.v1+wasm";
const OCI_MEDIA_TYPE: &str = "application/vnd.oci.image.layer.v1.tar";

fn determine_auth(
    image_reference: &str,
    creds_override: Option<HashMap<String, String>>,
) -> RegistryAuth {
    if let Some(hm) = creds_override {
        match (hm.get("username"), hm.get("password")) {
            (Some(un), Some(pw)) => {
                oci_distribution::secrets::RegistryAuth::Basic(un.to_string(), pw.to_string())
            }
            _ => oci_distribution::secrets::RegistryAuth::Anonymous,
        }
    } else {
        match (
            var(OCI_VAR_REGISTRY),
            var(OCI_VAR_USER),
            var(OCI_VAR_PASSWORD),
        ) {
            (Ok(reg), Ok(u), Ok(p)) if image_reference.starts_with(&reg) => {
                oci_distribution::secrets::RegistryAuth::Basic(u, p)
            }
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
    let img = &img.to_lowercase(); // the OCI spec does not allow for capital letters in references
    if !allow_latest && img.ends_with(":latest") {
        return Err(
            "Fetching images tagged 'latest' is currently prohibited in this host. This option can be overridden with WASMCLOUD_OCI_ALLOW_LATEST".into());
    }
    let cache_file = get_cached_filepath(img).await?;
    let digest_file = get_digest_filepath(img).await?;

    let auth = determine_auth(img, creds_override);
    let img = oci_distribution::Reference::from_str(img)?;

    let protocol = oci_distribution::client::ClientProtocol::HttpsExcept(allowed_insecure.to_vec());
    let config = oci_distribution::client::ClientConfig {
        protocol,
        ..Default::default()
    };
    let mut c = oci_distribution::Client::new(config);

    // In case of a cache miss where the file does not exist, pull a fresh OCI Image
    if tokio::fs::metadata(&cache_file).await.is_err() {
        let imgdata = pull(&mut c, &img, &auth).await;
        match imgdata {
            Ok(imgdata) => {
                cache_oci_image(imgdata, &cache_file, digest_file).await?;
            }
            Err(e) => return Err(format!("Failed to fetch OCI bytes: {}", e).into()),
        }
    } else {
        let manifest = c.pull_manifest(&img, &auth).await;
        match manifest {
            Ok(manifest) => {
                let (_, oci_digest) = manifest;
                // If the digest file doesn't exist that is ok, we just unwrap to an empty string
                let file_digest = tokio::fs::read_to_string(&digest_file)
                    .await
                    .unwrap_or_default();
                if oci_digest.is_empty() || file_digest.is_empty() || file_digest != oci_digest {
                    let imgdata = pull(&mut c, &img, &auth).await;
                    match imgdata {
                        Ok(imgdata) => {
                            cache_oci_image(imgdata, &cache_file, digest_file).await?;
                        }
                        Err(e) => return Err(format!("Failed to fetch OCI bytes: {}", e).into()),
                    }
                }
            }
            Err(e) => return Err(format!("Failed to fetch OCI manifest: {}", e).into()),
        }
    }

    Ok(cache_file)
}

async fn get_cached_filepath(img: &str) -> std::io::Result<PathBuf> {
    let mut path = create_filepath(img).await?;
    path.set_extension("bin");

    Ok(path)
}

async fn get_digest_filepath(img: &str) -> std::io::Result<PathBuf> {
    let mut path = create_filepath(img).await?;
    path.set_extension("digest");

    Ok(path)
}

async fn create_filepath(img: &str) -> std::io::Result<PathBuf> {
    let path = temp_dir();
    let path = path.join("wasmcloud_ocicache");
    ::tokio::fs::create_dir_all(&path).await?;
    // should produce a file like wasmcloud_azurecr_io_kvcounter_v1
    let img = img.replace(':', "_");
    let img = img.replace('/', "_");
    let img = img.replace('.', "_");
    let path = path.join(img);
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

async fn cache_oci_image(
    image: oci_distribution::client::ImageData,
    cache_filepath: impl AsRef<Path>,
    digest_filepath: impl AsRef<Path>,
) -> ::std::io::Result<()> {
    let mut cache_file = tokio::fs::File::create(cache_filepath).await?;
    let content = image
        .layers
        .into_iter()
        .flat_map(|l| l.data)
        .collect::<Vec<_>>();
    cache_file.write_all(&content).await?;
    cache_file.flush().await?;
    if let Some(digest) = image.digest {
        let mut digest_file = tokio::fs::File::create(digest_filepath).await?;
        digest_file.write_all(digest.as_bytes()).await?;
        digest_file.flush().await?;
    }
    Ok(())
}
