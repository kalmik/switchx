defmodule SwitchX.MixProject do
  use Mix.Project

  def project do
    [
      app: :switchx,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:ex_doc, "~> 0.18.0", only: :dev, runtime: false}
    ]
  end
end
