defmodule TriviaAdvisor.Scraping.Scrapers.Inquizition.Scraper do
  require Logger
  alias TriviaAdvisor.Scraping.Scrapers.Inquizition.TimeParser
  alias TriviaAdvisor.Locations.VenueStore
  alias TriviaAdvisor.{Events, Repo, Scraping}

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
            # Get source for logging
            source = Repo.get_by!(Scraping.Source, name: "inquizition")
            start_time = DateTime.utc_now()

            results = html
              |> Floki.parse_document!()
              |> Floki.find(".storelocator-store")
              |> Enum.map(&parse_venue/1)
              |> Enum.reject(&is_nil/1)

            # Calculate statistics
            total_venues = length(results)
            successful_venues = Enum.count(results, &match?([ok: _], &1))
            failed_venues = total_venues - successful_venues

            # Create scrape log
            Scraping.create_scrape_log(%{
              source_id: source.id,
              start_time: start_time,
              end_time: DateTime.utc_now(),
              total_venues: total_venues,
              successful_venues: successful_venues,
              failed_venues: failed_venues,
              metadata: %{
                "retries" => retries
              }
            })

            Logger.info("""
            📊 Scrape Summary:
            Total venues: #{total_venues}
            Successfully processed: #{successful_venues}
            Failed to process: #{failed_venues}
            """)

            results

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

    # Prefix with underscore since we're not using it yet
    _email =
      store
      |> Floki.find(".storelocator-email a")
      |> Floki.attribute("href")
      |> List.first()
      |> case do
        "mailto:" <> email_addr -> email_addr
        _ -> nil
      end

    website =
      store
      |> Floki.find("a")
      |> Enum.find(fn elem ->
        Floki.text(elem) |> String.trim() == "Website"
      end)
      |> case do
        nil -> nil
        elem -> elem |> Floki.attribute("href") |> List.first()
      end

    if title != "" do
      # Parse time data
      parsed_time = case TimeParser.parse_time(time_text) do
        {:ok, data} -> data
        {:error, reason} ->
          Logger.warning("⚠️ Could not parse time: #{reason}")
          %{day_of_week: nil, start_time: nil, frequency: nil}
      end

      # Log venue details
      Logger.info("""
      🏠 Processing venue: #{title}
      Address: #{address}
      Time: #{time_text}
      Phone: #{phone}
      Website: #{website}
      """)

      # Create venue data map
      venue_data = %{
        name: title,
        address: address,
        phone: phone,
        website: website
      }

      # Try to find or create venue
      case VenueStore.process_venue(venue_data) do
        {:ok, venue} ->
          Logger.info("✅ Successfully processed venue: #{venue.name}")

          # Get source from seeds
          source = Repo.get_by!(TriviaAdvisor.Scraping.Source, name: "inquizition")

          # Create or update event
          case Events.find_or_create_event(%{
            name: "Inquizition Quiz at #{venue.name}",
            venue_id: venue.id,
            day_of_week: parsed_time.day_of_week,
            start_time: parsed_time.start_time,
            frequency: parsed_time.frequency,
            entry_fee_cents: 250, # Standard £2.50 fee
            description: time_text
          }) do
            {:ok, event} ->
              # Create event source record
              case Events.create_event_source(%{
                event_id: event.id,
                source_id: source.id,
                source_url: "inquizition",
                metadata: %{
                  "description" => time_text,
                  "time_text" => time_text
                }
              }) do
                {:ok, _event_source} -> [ok: venue]
                error ->
                  Logger.error("Failed to create event source: #{inspect(error)}")
                  nil
              end

            error ->
              Logger.error("Failed to create event: #{inspect(error)}")
              nil
          end

        error ->
          Logger.error("❌ Failed to process venue: #{inspect(error)}")
          nil
      end
    end
  end

  defp parse_venue(_), do: nil
end
