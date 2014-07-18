defmodule Logger.Handler do
  use GenEvent

  def init(_) do
    # TODO: Consider the user when calculating the handlers state
    # No user means tty is always disabled.
    if user = Process.whereis(:user) do
      Process.group_leader(self(), user)
    end

    {:ok, %{handlers: [], user: user}}
  end

  ## Handle call

  def handle_call({:enable, handler}, state) do
    state = update_in(state.handlers, fn handlers ->
      [handler|List.delete(handlers, handler)]
    end)
    {:ok, :ok, state}
  end

  def handle_call({:disable, handler}, state) do
    state = update_in(state.handlers, &List.delete(&1, handler))
    {:ok, :ok, state}
  end

  ## Handle event

  def handle_event({_type, gl, _msg}, state) when node(gl) != node() do
    {:ok, state}
  end

  def handle_event(_, %{handlers: []} = state) do
    {:ok, state}
  end

  def handle_event(event, state) do
    state = log_event(event, state)
    {:ok, state}
  end

  ## Handle info

  @offband_levels [:debug]

  def handle_info({type, gl, _msg} = event, state) when node(gl) != node() and type in @offband_levels do
    send {:error_logger, node(gl)}, event
    {:ok, state}
  end

  def handle_info({type, _gl, _msg} = event, state) when type in @offband_levels do
    state = log_event(event, state)
    {:ok, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  ## Helpers

  defp log_event({:debug, _gl, {pid, {Logger, meta}, format}}, state),
    do: log_event(:debug, :message, pid, format, meta, state)

  defp log_event({:error, _gl, {pid, format, data}}, state),
    do: log_event(:error, :format, pid, {format, data}, [], state)
  defp log_event({:error_report, _gl, {pid, :std_error, format}}, state),
    do: log_event(:error, :report, pid, format, [], state)
  defp log_event({:error_report, _gl, {pid, {Logger, meta}, format}}, state),
    do: log_event(:error, :message, pid, format, meta, state)
  defp log_event({:error_report, _gl, _}, state),
    do: state

  defp log_event({:warning_msg, _gl, {pid, format, data}}, state),
    do: log_event(:warning, :format, pid, {format, data}, [], state)
  defp log_event({:warning_report, _gl, {pid, :std_warning, format}}, state),
    do: log_event(:warning, :report, pid, format, [], state)
  defp log_event({:warning_report, _gl, {pid, {Logger, meta}, format}}, state),
    do: log_event(:warning, :message, pid, format, meta, state)
  defp log_event({:warning_report, _gl, _}, state),
    do: state

  defp log_event({:info_msg, _gl, {pid, format, data}}, state),
    do: log_event(:info, :format, pid, {format, data}, [], state)
  defp log_event({:info_report, _gl, {pid, :std_info, format}}, state),
    do: log_event(:info, :report, pid, format, [], state)
  defp log_event({:info_report, _gl, {pid, {Logger, meta}, format}}, state),
    do: log_event(:info, :message, pid, format, meta, state)
  defp log_event({:info_report, _gl, _}, state),
    do: state

  # TODO: Support custom formatters (new line is a formatter concern)
  # TODO: Support high watermark
  # TODO: Add node to report if node(pid) != node()
  # TODO: Support level for erlang messages (elixir ones are handled on client)
  # TODO: Truncate erlang messages (elixir ones are truncated on client)
  defp log_event(level, kind, pid, data, _metadata, state) do
    formatted = format_event(level, kind, data)
    time = :erlang.universaltime
    for handler <- state.handlers do
      log_event(handler, time, level, pid, formatted)
    end
    state
  end

  defp format_event(_level, :message, format), do: [format, ?\n]
  defp format_event(_level, :report, format), do: [Kernel.inspect(format), ?\n]
  defp format_event(_level, :format, {format, args}) do
    {format, args} = Logger.Formatter.inspect(format, args)
    :io_lib.format(format, args)
  end

  defp log_event(:tty, time, level, _pid, formatted) do
    :io.put_chars :user, [format_time(time), ?\s, format_level(level), ?\s, formatted]
  end

  defp format_time({{yy, mm, dd}, {hh, mi, ss}}) do
    [pad(yy), ?-, pad(mm), ?-, pad(dd), ?\s, pad(hh), ?:, pad(mi), ?:, pad(ss)]
  end

  defp pad(int) when int < 10, do: [?0, Integer.to_string(int)]
  defp pad(int), do: Integer.to_string(int)

  defp format_level(:warning), do: "[warning]"
  defp format_level(:debug),   do: "[debug]"
  defp format_level(:error),   do: "[error]"
  defp format_level(:info),    do: "[info]"
end