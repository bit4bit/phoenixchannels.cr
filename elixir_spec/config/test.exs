import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :elixir_spec, ElixirSpecWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "00J9D7kFeanwGe5wnt2SauhV8CigAJUL00GH16Nf+v3bsMt2/cstjt9BxPX+QhJv",
  server: false

# In test we don't send emails.
config :elixir_spec, ElixirSpec.Mailer,
  adapter: Swoosh.Adapters.Test

# Print only warnings and errors during test
config :logger, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
