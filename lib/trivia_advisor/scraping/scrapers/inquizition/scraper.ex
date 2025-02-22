defmodule TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper do
  require Logger

  @base_url "https://inquizition.com"
  @find_quiz_url "#{@base_url}/find-a-quiz/"
  @zyte_api_url "https://api.zyte.com/v1/extract"
  @max_retries 3
  @timeout 60_000

  def scrape do
    # Load .env file if it exists
    if File.exists?(".env") do
      DotenvParser.load_file(".env")
      Logger.info("📝 Loaded .env file")
    end

    # Verify API key is available
    case System.get_env("ZYTE_API_KEY") do
      key when is_binary(key) and byte_size(key) > 0 ->
        Logger.info("🔑 Zyte API key loaded successfully")
        do_scrape(key)

      _ ->
        Logger.error("❌ ZYTE_API_KEY not found in environment")
        []
    end
  end

  defp do_scrape(api_key, retries \\ 0) do
    headers = [
      {"Authorization", "Basic #{Base.encode64(api_key <> ":")}"},
      {"Content-Type", "application/json"}
    ]

    body = Jason.encode!(%{
      url: @find_quiz_url,
      browserHtml: true,
      javascript: true,
      # Add viewport size to ensure map loads properly
      viewport: %{
        width: 1920,
        height: 1080
      }
    })

    options = [
      timeout: @timeout,
      recv_timeout: @timeout,
      hackney: [pool: :default]
    ]

    case HTTPoison.post(@zyte_api_url, body, headers, options) do
      {:ok, %{status_code: 200, body: response}} ->
        case Jason.decode(response) do
          {:ok, %{"browserHtml" => html}} ->
            html
            |> Floki.parse_document!()
            |> Floki.find(".storelocator-store")
            |> Enum.map(&parse_venue/1)
            |> Enum.reject(&is_nil/1)
            |> tap(&Logger.info("Found #{length(&1)} venues"))

          error ->
            Logger.error("Failed to parse Zyte response: #{inspect(error)}")
            retry_or_fail(api_key, retries, "JSON parsing failed")
        end

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("Zyte API error (#{status}): #{body}")
        retry_or_fail(api_key, retries, "HTTP #{status}")

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("Failed to fetch from Zyte: #{inspect(reason)}")
        retry_or_fail(api_key, retries, "HTTP error: #{inspect(reason)}")
    end
  end

  defp retry_or_fail(_api_key, retries, error) when retries >= @max_retries do
    Logger.error("Max retries (#{@max_retries}) reached. Last error: #{error}")
    []
  end

  defp retry_or_fail(api_key, retries, error) do
    new_retries = retries + 1
    Logger.info("Retrying request (attempt #{new_retries}/#{@max_retries}). Previous error: #{error}")
    Process.sleep(1000 * new_retries) # Exponential backoff
    do_scrape(api_key, new_retries)
  end

  defp parse_venue(store) when is_tuple(store) do
    title = store |> Floki.find(".storelocator-storename") |> Floki.text() |> String.trim()
    time_text = store |> Floki.find(".storelocator-description") |> Floki.text() |> String.trim()

    address =
      store
      |> Floki.find(".storelocator-address")
      |> Floki.text()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(", ")

    phone =
      store
      |> Floki.find(".storelocator-phone a")
      |> Floki.text()
      |> String.trim()

    email =
      store
      |> Floki.find(".storelocator-email a")
      |> Floki.attribute("href")
      |> List.first()
      |> case do
        "mailto:" <> email_addr -> email_addr
        _ -> nil
      end

    if title != "" do
      venue_data = %{
        raw_title: title,
        name: title,
        address: address,
        time_text: time_text,
        fee_text: "FREE",
        phone: phone,
        email: email
      }

      Logger.info("""
      Found venue:
        Title: #{title}
        Time: #{time_text}
        Address: #{address}
        Phone: #{phone}
        Email: #{email}
      """)

      venue_data
    end
  end

  defp parse_venue(_), do: nil
end
