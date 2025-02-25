defmodule TriviaAdvisor.Scraping.Scrapers.GeeksWhoDrink.NonceExtractor do
  require Logger

  @venues_url "https://www.geekswhodrink.com/venues/"

  def fetch_nonce do
    Logger.info("🔍 Fetching nonce from Geeks Who Drink venues page...")

    case HTTPoison.get(@venues_url) do
      {:ok, %{status_code: 200, body: body}} ->
        extract_nonce_from_html(body)

      {:ok, %{status_code: status}} ->
        Logger.error("❌ Failed to fetch venues page: HTTP #{status}")
        {:error, "HTTP request failed with status #{status}"}

      {:error, error} ->
        Logger.error("❌ Failed to fetch venues page: #{inspect(error)}")
        {:error, error}
    end
  end

  defp extract_nonce_from_html(body) do
    case Regex.run(~r/gwdNonce":\s*"([^"]+)"/, body) do
      [_, nonce] ->
        Logger.info("✅ Successfully extracted nonce: #{nonce}")
        {:ok, nonce}

      nil ->
        Logger.error("❌ Could not find nonce in page content")
        {:error, :nonce_not_found}
    end
  end
end
