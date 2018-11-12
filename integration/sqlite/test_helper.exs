Logger.configure(level: :info)
ExUnit.start exclude: [:array_type,
                       :strict_savepoint,
                       :update_with_join,
                       :delete_with_join,
                       :foreign_key_constraint,
                       :modify_column,
                       :modify_foreign_key,
                       :prefix,
                       :remove_column,
                       :rename_column,
                       :right_join,
                       :unique_constraint,
                       :uses_usec,
                       :transaction_isolation,
                       :insert_cell_wise_defaults,
                       :modify_foreign_key_on_delete,
                       :modify_foreign_key_on_update,
                       :alter_primary_key,
                       :map_boolean_in_subquery,
                       :upsert_all,
                       :with_conflict_target,
                       :without_conflict_target,
                       :decimal_type,
                       :cross_join
                      ]

# Configure Ecto for support and tests
Application.put_env(:ecto, :primary_key_type, :id)

# Old Ecto files don't compile cleanly in Elixir 1.4, so we disable warnings first.
case System.version() do
  "1.4." <> _ -> Code.compiler_options(warnings_as_errors: false)
  _ -> :ok
end

pool =
  case System.get_env("ECTO_POOL") || "poolboy" do
    "poolboy"        -> DBConnection.Poolboy
    "sojourn_broker" -> DBConnection.Sojourn
  end

# Load support files
Code.require_file "../../deps/ecto/integration_test/support/repo.exs", __DIR__
Code.require_file "../../deps/ecto/integration_test/support/schemas.exs", __DIR__
Code.require_file "../../deps/ecto/integration_test/support/migration.exs", __DIR__

Code.require_file "../../test/support/schemas.exs", __DIR__
Code.require_file "../../test/support/migration.exs", __DIR__

# Pool repo for async, safe tests
alias Ecto.Integration.TestRepo

Application.put_env(:ecto, TestRepo,
  adapter: Sqlite.Ecto2,
  database: "/tmp/test_repo.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  ownership_pool: pool)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Integration.Repo, otp_app: :ecto
end

# Pool repo for non-async tests
alias Ecto.Integration.PoolRepo

Application.put_env(:ecto, PoolRepo,
  adapter: Sqlite.Ecto2,
  pool: DBConnection.Poolboy,
  database: "/tmp/test_repo.db",
  pool_size: 10)

defmodule Ecto.Integration.PoolRepo do
  use Ecto.Integration.Repo, otp_app: :ecto

  def create_prefix(prefix) do
    "create schema #{prefix}"
  end

  def drop_prefix(prefix) do
    "drop schema #{prefix}"
  end
end

defmodule Ecto.Integration.Case do
  use ExUnit.CaseTemplate

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
  end
end

{:ok, _} = Sqlite.Ecto2.ensure_all_started(TestRepo, :temporary)

# Load support models and migration
Code.require_file "../../deps/ecto/integration_test/support/schemas.exs", __DIR__
Code.require_file "../../deps/ecto/integration_test/support/migration.exs", __DIR__

# Load up the repository, start it, and run migrations
_   = Sqlite.Ecto2.storage_down(TestRepo.config)
:ok = Sqlite.Ecto2.storage_up(TestRepo.config)

{:ok, _pid} = TestRepo.start_link
{:ok, _pid} = PoolRepo.start_link

:ok = Ecto.Migrator.up(TestRepo, 0, Ecto.Integration.Migration, log: false)
:ok = Ecto.Migrator.up(TestRepo, 1, Sqlite.Ecto2.Test.Migration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
