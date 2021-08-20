defmodule WasmcloudHostWeb.MetricsLive do
  use Phoenix.LiveView

  def render(assigns) do
    ~L"""
    <main class="c-main">
      <div class="container-fluid">
        <div class="fade-in">
          <div class="row">
              <div class="col-sm-12 col-md-12">
                <div class="card">
                    <div class="col-lg-12 col-md-12 col-sm-12">
                      <div class="card-header">
                          Erlang Metrics for
                          <button class="btn btn-secondary btn-sm" type="button" onClick="navigator.clipboard.writeText('<%= HostCore.Host.host_key() %>')" data-toggle="popover" data-trigger="focus" title="" data-content="Copied!">
                            <%= String.slice(HostCore.Host.host_key(), 0..4) %>...
                            <svg class="c-icon">
                                <use xlink:href="/coreui/free.svg#cil-copy"></use>
                            </svg>
                          </button>
                      </div>
                      <div class="card-body">
                          <div class="row">
                            <div class="col-sm-6 col-md-2">
                                <div class="card text-white bg-gradient-info">
                                  <div class="card-body">
                                      <div class="text-muted text-right mb-4">
                                        <svg class="c-icon c-icon-2xl">
                                            <use xlink:href="/coreui/free.svg#cil-data-transfer-down"></use>
                                        </svg>
                                      </div>
                                      <div class="text-value-lg"><%= {{:input, num}, _out} = :erlang.statistics(:io); num / 1_000_000 |> Float.round(2)%> MB</div>
                                      <small class="text-muted text-uppercase font-weight-bold">Input</small>
                                  </div>
                                </div>
                            </div>
                            <!-- /.col-->
                            <div class="col-sm-6 col-md-2">
                                <div class="card text-white bg-gradient-success">
                                  <div class="card-body">
                                      <div class="text-muted text-right mb-4">
                                        <svg class="c-icon c-icon-2xl">
                                            <use xlink:href="/coreui/free.svg#cil-data-transfer-up"></use>
                                        </svg>
                                      </div>
                                      <div class="text-value-lg"><%= {_input, {:output, num}} = :erlang.statistics(:io); num / 1_000_000 |> Float.round(2)%> MB</div>
                                      <small class="text-muted text-uppercase font-weight-bold">Output</small>
                                  </div>
                                </div>
                            </div>
                            <!-- /.col-->
                            <div class="col-sm-6 col-md-2">
                                <div class="card text-white bg-gradient-warning">
                                  <div class="card-body">
                                      <div class="text-muted text-right mb-4">
                                        <svg class="c-icon c-icon-2xl">
                                            <use xlink:href="/coreui/free.svg#cil-vector"></use>
                                        </svg>
                                      </div>
                                      <div class="text-value-lg"><%= processes = :erlang.system_info(:process_count); processes %></div>
                                      <small class="text-muted text-uppercase font-weight-bold">OTP Processes</small>
                                  </div>
                                </div>
                            </div>
                            <!-- /.col-->
                            <div class="col-sm-6 col-md-2">
                                <div class="card text-white bg-gradient-danger">
                                  <div class="card-body">
                                      <div class="text-muted text-right mb-4">
                                        <svg class="c-icon c-icon-2xl">
                                            <use xlink:href="/coreui/free.svg#cil-clock"></use>
                                        </svg>
                                      </div>
                                      <div class="text-value-lg">
                                        <%= {time, _since_last} = :erlang.statistics(:wall_clock)
                                            seconds = round(time / 1_000)
                                            minutes = floor(seconds / 60)

                                            seconds = rem(seconds, 60)
                                            hours = floor(minutes / 60)
                                            minutes = rem(minutes, 60)
                                            "#{hours}H #{minutes}M #{seconds}S"
                                            %>
                                      </div>
                                      <small class="text-muted text-uppercase font-weight-bold">Host Uptime</small>
                                  </div>
                                </div>
                            </div>
                            <!-- /.col-->
                            <div class="col-sm-6 col-md-2">
                                <div class="card text-white bg-gradient-primary">
                                  <div class="card-body">
                                      <div class="text-muted text-right mb-4">
                                        <svg class="c-icon c-icon-2xl">
                                            <use xlink:href="/coreui/free.svg#cil-screen-desktop"></use>
                                        </svg>
                                      </div>
                                      <div class="text-value-lg"><%= :erlang.system_info(:otp_release) %></div>
                                      <small class="text-muted text-uppercase font-weight-bold">OTP Release</small>
                                  </div>
                                </div>
                            </div>
                            <!-- /.col-->
                            <div class="col-sm-6 col-md-2">
                                <div class="card text-white bg-gradient-success">
                                  <div class="card-body">
                                      <div class="text-muted text-right mb-4">
                                        <img class="c-icon c-icon-2xl" src="/images/wasmcloud_inversed_square.png" alt="wasmCloud logo">
                                      </div>
                                      <div class="text-value-lg"><%= Application.get_env(:wasmcloud_host, :app_version) %></div>
                                      <small class="text-muted text-uppercase font-weight-bold">wasmCloud Release</small>
                                  </div>
                                </div>
                            </div>
                            <!-- /.col-->
                          </div>
                      </div>
                    </div>
                    <div class="card-footer">
                      Metrics are only currently supported for the host running alongside the dashboard.
                    </div>
                </div>
              </div>
          </div>
        </div>
      </div>
    </main>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
