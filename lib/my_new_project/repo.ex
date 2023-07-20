defmodule MyNewProject.Repo do
  use Ecto.Repo,
    otp_app: :my_new_project,
    adapter: Ecto.Adapters.Postgres
end
