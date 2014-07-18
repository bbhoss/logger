defmodule Logger do
  use Application

  @moduledoc """
  A logger for Elixir applications.

  ## Level

  The supported levels are:

    * `:debug` - for debug-related messages
    * `:info` - for information of any kind
    * `:warn` - for warnings
    * `:error` - for errors

  ## Logger Configuration

    * `:backends` - the backends to be used. Defaults to `[:tty]`
      only. See the "Backends" section for more information.

    * `:truncate` - the maximum message size to be logged. Defaults
      to 8192 bytes. Note this configuration is approximate. Truncated
      messages will have "(truncated)" at the end.

  At runtime, `Logger.configure/1` must be used to configure Logger
  options, which guarantees the configuration is serialized and
  properly reloaded.

  ## Erlang's error_logger redirect configuration

  The following configuration applies to the Logger functionality
  where messages sent to Erlang's error_logger are redirected to
  to Logger.

  All the configurations below must be set before the application
  starts in order to take effect.

    * `:handle_otp_reports` - redirects OTP reports to Logger so
      they are formatted in Elixir terms. This uninstalls Erlang's
      logger that prints terms to terminal.

    * `:handle_sasl_reports` - redirects SASL reports to Logger so
      they are formatted in Elixir terms. This uninstalls SASL's
      logger that prints terms to terminal as long as the SASL
      application is started before Logger.

    * `:discard_threshold_for_error_logger` - a value that, when
      reached, triggers the error logger to discard messages. This
      value must be a positive number that represents the maximum
      number of messages accepted per second. Once above this
      threshold, the error_logger enters in discard mode for the
      remaining of that second.

  ## Backends

  The supported backends are:

    * `:tty` - log entries to the terminal (enabled by default)

  ## Comparison to Erlang's error_logger

  Logger includes many improvements over OTP's error logger such as:

    * it adds a new log level named debug.

    * it guarantees event handlers are restarted on crash.

    * it formats messages on the client to avoid clogging
      the logger event manager.

    * it truncates error messages to avoid large log messages.

  """

  @type handler :: :tty
  @type level :: :error | :info | :warn | :debug

  @levels [:error, :info, :warn, :debug]

  @doc false
  def start(_type, _args) do
    import Supervisor.Spec

    options  = [strategy: :one_for_one, name: Logger.Supervisor]
    children = [worker(GenEvent, [[name: Logger]]),
                supervisor(Logger.Watcher, []),
                worker(Logger.Config, [])]

    {:ok, sup} = Supervisor.start_link(children, options)

    otp_reports?   = Application.get_env(:logger, :handle_otp_reports)
    sasl_reports?  = Application.get_env(:logger, :handle_sasl_reports)
    reenable_tty?  = delete_error_logger_handler(otp_reports?, :error_logger_tty_h)
    reenable_sasl? = delete_error_logger_handler(sasl_reports?, :sasl_report_tty_h)

    threshold = Application.get_env(:logger, :discard_threshold_for_error_logger)
    Logger.Watcher.watch(:error_logger, Logger.ErrorHandler,
      {otp_reports?, sasl_reports?, threshold})

    # TODO: Start this based on the backends config
    # TODO: Runtime backend configuration
    Logger.Watcher.watch(Logger, Logger.Backends.TTY, :ok)

    {:ok, sup, {reenable_tty?, reenable_sasl?}}
  end

  @doc false
  def stop({reenable_tty?, reenable_sasl?}) do
    add_error_logger_handler(reenable_tty?, :error_logger_tty_h)
    add_error_logger_handler(reenable_sasl?, :sasl_report_tty_h)

    # We need to do this in another process as the Application
    # Controller is currently blocked shutting down this app.
    spawn_link(fn -> Logger.Config.clear_data end)

    :ok
  end

  defp add_error_logger_handler(was_enabled?, handler) do
    was_enabled? and :error_logger.add_report_handler(handler)
    :ok
  end

  defp delete_error_logger_handler(should_delete?, handler) do
    should_delete? and
      :error_logger.delete_report_handler(handler) != {:error, :module_not_found}
  end

  @doc """
  Configures the logger.

  See the "Configuration" section in `Logger` module documentation
  for the available options.
  """
  def configure(options) do
    Logger.Config.configure(options)
  end

  @doc """
  Logs a message.

  Developers should rather use the macros `Logger.debug/2`,
  `Logger.warn/2`, `Logger.info/2` or `Logger.error/2` instead
  of this function as they automatically include caller metadata.

  Use this function only when there is a need to log dynamically
  or you want to explicitly avoid embedding metadata.
  """
  @spec log(level, IO.chardata | (() -> IO.chardata), Keyword.t) :: :ok
  def log(level, chardata, metadata \\ []) when level in @levels and is_list(metadata) do
    # TODO: Consider log level
    # TODO: Handle async/sync modes
    unless Process.whereis(Logger) do
      raise "Cannot log messages, the :logger application is not running"
    end

    {truncate, _} = Logger.Config.__data__
    notify(level, truncate(chardata, truncate), metadata)
  end

  @doc """
  Logs a warning.

  ## Examples

      Logger.warn "knob turned too much to the right"
      Logger.warn fn -> "expensive to calculate warning" end

  """
  defmacro warn(chardata, metadata \\ []) do
    quote do
      Logger.log(:warn, unquote(chardata), unquote(metadata))
    end
  end

  @doc """
  Logs some info.

  ## Examples

      Logger.info "mission accomplished"
      Logger.info fn -> "expensive to calculate info" end

  """
  defmacro info(chardata, metadata \\ []) do
    quote do
      Logger.log(:info, unquote(chardata), unquote(metadata))
    end
  end

  @doc """
  Logs an error.

  ## Examples

      Logger.error "oops"
      Logger.error fn -> "expensive to calculate error" end

  """
  defmacro error(chardata, metadata \\ []) do
    quote do
      Logger.log(:error, unquote(chardata), unquote(metadata))
    end
  end

  @doc """
  Logs a debug message.

  ## Examples

      Logger.debug "hello?"
      Logger.debug fn -> "expensive to calculate debug" end

  """
  defmacro debug(chardata, metadata \\ []) do
    quote do
      Logger.log(:debug, unquote(chardata), unquote(metadata))
    end
  end

  defp truncate(data, n) when is_function(data, 0) do
    Logger.Formatter.truncate(data.(), n)
  end

  defp truncate(data, n) when is_list(data) or is_binary(data) do
    Logger.Formatter.truncate(data, n)
  end

  defp notify(level, chardata, metadata) do
    GenEvent.notify(Logger,
      {level, Process.group_leader(),
        {self(), {Logger, metadata}, chardata}})
  end
end
