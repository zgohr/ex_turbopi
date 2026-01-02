import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ex_turbopi_web, ExTurbopiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZCTZn8oSAym0vU9xIG8m7l2S8r1MKlUO/prwgqQ+o+Qd+YHwE9EmMODoplTevjRv",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
