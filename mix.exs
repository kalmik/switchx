defmodule SwitchX.MixProject do
  use Mix.Project

  def project do
    [
      app: :switchx,
      version: "1.0.1",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),

      # Docs
      name: "SwitchX",
      source_url: "https://github.com/kalmik/switchx",
      homepage_url: "",
      docs: [
        main: "SwitchX",
        extras: ["README.md"]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support", "lib"]
  defp elixirc_paths(:dev), do: ["examples", "lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp package() do
    [
      description: "FreeSWITCH Event Socket Protocol client implementation with  Elixir",
      # These are the default files included in the package
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/kalmik/switchx"}
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :telemetry,]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:mock, "~> 0.3.0", only: :test},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end
end
