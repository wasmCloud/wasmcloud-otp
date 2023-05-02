defmodule HostCore.CopyNIF do
  alias Burrito.Builder.Step
  @behaviour Step

  @impl Step
  def execute(%Burrito.Builder.Context{} = context) do
    dir =
      Path.join(context.work_dir, [
        "lib",
        "/host_core-#{context.mix_release.version}",
        "/priv",
        "/native"
      ])

    File.mkdir_p!(dir)

    case context.target.alias do
      :aarch64_darwin ->
        File.copy!(
          System.get_env("NIF_AARCH64_DARWIN"),
          Path.join(dir, "libhostcore_wasmcloud_native.so")
        )

      :aarch64_linux_gnu ->
        File.copy!(
          System.get_env("NIF_AARCH64_LINUX_GNU"),
          Path.join(dir, "libhostcore_wasmcloud_native.so")
        )

      :aarch64_linux_musl ->
        File.copy!(
          System.get_env("NIF_AARCH64_LINUX_MUSL"),
          Path.join(dir, "libhostcore_wasmcloud_native.so")
        )

      :x86_64_darwin ->
        File.copy!(
          System.get_env("NIF_X86_64_DARWIN"),
          Path.join(dir, "libhostcore_wasmcloud_native.so")
        )

      :x86_64_linux_gnu ->
        File.copy!(
          System.get_env("NIF_X86_64_LINUX_GNU"),
          Path.join(dir, "libhostcore_wasmcloud_native.so")
        )

      :x86_64_linux_musl ->
        File.copy!(
          System.get_env("NIF_X86_64_LINUX_MUSL"),
          Path.join(dir, "libhostcore_wasmcloud_native.so")
        )

      :x86_64_windows ->
        File.copy!(
          System.get_env("NIF_X86_64_WINDOWS"),
          Path.join(dir, "libhostcore_wasmcloud_native.dll")
        )

      alias ->
        raise "unknown target alias #{inspect(alias)}"
    end

    context
  end
end
