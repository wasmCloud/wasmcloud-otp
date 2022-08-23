# Import all plugins from `rel/plugins`
# They can then be used by adding `plugin MyPlugin` to
# either an environment, or release definition, where
# `MyPlugin` is the name of the plugin module.
~w(rel plugins *.exs)
|> Path.join()
|> Path.wildcard()
|> Enum.map(&Code.eval_file(&1))

# You may define one or more environments in this file,
# an environment's settings will override those of a release
# when building in that environment, this combination of release
# and environment configuration is called a profile

environment :dev do
  # If you are running Phoenix, you should make sure that
  # server: true is set and the code reloader is disabled,
  # even in dev mode.
  # It is recommended that you build with MIX_ENV=prod and pass
  # the --env flag to Distillery explicitly if you want to use
  # dev mode.
  set(dev_mode: true)
  set(include_erts: false)
  set(cookie: :"n4LfA8^YJb7}3H22ww}cFSSorOheasB|Fz/88$x}BfZ;CC>X9Z}j_6WgKxiW]CY>")
end

environment :prod do
  set(include_erts: true)
  set(include_src: false)
  set(cookie: :"@{c_aB(}`DdY[Jio}f9yF~!j_b$~>`Iy;=oY&TV{P{d2i|Zz~7DIB5Hj%yq[C]E^")
  set(vm_args: "rel/vm.args")
end
