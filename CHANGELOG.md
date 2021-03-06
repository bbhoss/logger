# v0.4.0

* [Logger] Support custom backends
* [Logger] Support custom translators

# v0.3.0

* [Logger] Requires Elixir master
* [Logger] Improve truncation algorithms to avoid overflow
* [Logger] Alternate between sync and async modes
* [Logger] Prune messages based on logger level
* [Logger] Provides custom formatting and API for customizing backends
* [Logger] Allow users to choose in between utc or local time logging (defaults to local time)

# v0.2.0

* [Logger] Add debug level
* [Logger] Add data truncation
* [Logger] Add lazily calculated messages with functions
* [Logger] Add a discard threshold for the error logger

# v0.1.0

* [Logger] Logger provides API for emitting error/info/warning messages
* [Logger] Logger formats Erlang' error/info/warning messages in Elixir terms
* [Logger] Logger provides a watcher to ensure the error logger handler is always reinstalled
