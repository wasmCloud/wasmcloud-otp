## Recommendation for future reference

1. Nesting of modules in Elixir, while possible, is not recommended (mainly because it can affect readability) and neither does it affect discovery of the module.

2. In case you need to achieve something similar to this, it's okay to define multiple modules within the same file (this is done a lot throughout the Elixir source code)

   As an example, this can be refactored to:

   ```elixir
   # actor_module.ex
   defmodule State do
   @moduledoc false

       defstruct [
       :guest_request,
       :guest_response,
       :host_response,
       :guest_error,
       :host_error,
       :instance,
       :instance_id,
       :annotations,
       :api_version,
       :invocation,
       :claims,
       :ociref,
       :healthy,
       :parent_span
       ]
   end

   defmodule Invocation do
       @moduledoc false
       defstruct [:operation, :payload]
   end

   defmodule HostCore.Actors.ActorModule do
       @moduledoc false

       ## rest of your module
   end


   ```
