# test_pubquiz_extraction.exs
# Run with: mix run lib/scripts/test_pubquiz_extraction.exs

Logger.configure(level: :debug)
require Logger

# Polish day mapping (same as in PubquizDetailJob)
polish_days = %{
  "PONIEDZIAŁEK" => 1,
  "WTOREK" => 2,
  "ŚRODA" => 3,
  "CZWARTEK" => 4,
  "PIĄTEK" => 5,
  "SOBOTA" => 6,
  "NIEDZIELA" => 0
}

# Sample venue URLs to test
venue_urls = [
  "https://pubquiz.pl/kategoria-produktu/bydgoszcz/cybermachina-bydgoszcz/",
  "https://pubquiz.pl/kategoria-produktu/bydgoszcz/pasibus/",
  "https://pubquiz.pl/kategoria-produktu/gdansk/green-club/"
]

# Extraction function (simplified version of what's in PubquizDetailJob)
extract_event_details = fn body ->
  # Extract product titles which contain day and time info
  product_titles = Regex.scan(~r/<h3 class="product-title">(.*?)<\/h3>/s, body)
    |> Enum.map(fn [_, title] -> title end)

  IO.puts("Found product titles: #{inspect(product_titles)}")

  # Try several different regex patterns for price extraction
  price_patterns = [
    # Pattern 1: Standard format
    ~r/<span class="woocommerce-Price-amount amount">(.*?)&nbsp;<span class="woocommerce-Price-currencySymbol">zł<\/span><\/span>/s,
    # Pattern 2: Alternative format
    ~r/<span class="product-price price"><span class="woocommerce-Price-amount amount">(.*?)&nbsp;<span class="woocommerce-Price-currencySymbol">zł<\/span><\/span>/s,
    # Pattern 3: More general pattern
    ~r/<span class="woocommerce-Price-amount amount">(.*?)&nbsp;/s
  ]

  # Try each pattern until we find prices
  price_texts = Enum.reduce_while(price_patterns, [], fn pattern, acc ->
    results = Regex.scan(pattern, body) |> Enum.map(fn [_, price] -> price end)
    if Enum.empty?(results), do: {:cont, acc}, else: {:halt, results}
  end)

  IO.puts("Found price texts: #{inspect(price_texts)}")

  # Look for the iworks-omnibus divs which might contain price info
  omnibus_divs = Regex.scan(~r/<p class="iworks-omnibus".*?data-iwo-price="(.*?)".*?>/s, body)
    |> Enum.map(fn [_, price] -> price end)
  IO.puts("Found omnibus price data: #{inspect(omnibus_divs)}")

  if Enum.empty?(product_titles) do
    IO.puts("⚠️ No product titles found on page")
    {1, ~T[19:00:00], 0} # Default values if nothing found
  else
    # Take the first product as representative
    product_title = List.first(product_titles)
    IO.puts("Using product title: #{product_title}")

    # Extract day of week from within brackets [DAY]
    day_of_week = case Regex.run(~r/\[(.*?)\]/, product_title) do
      [_, polish_day] ->
        numeric_day = Map.get(polish_days, polish_day, 1)
        IO.puts("Extracted day of week: #{polish_day} -> #{numeric_day}")
        numeric_day
      _ ->
        IO.puts("⚠️ Could not extract day of week from title: #{product_title}")
        1 # Default to Monday if not found
    end

    # Extract time (usually at the end of the title like "20:00")
    start_time = case Regex.run(~r/(\d{2}:\d{2})$/, product_title) do
      [_, time_str] ->
        [hours, minutes] = String.split(time_str, ":")
        time = Time.new!(String.to_integer(hours), String.to_integer(minutes), 0)
        IO.puts("Extracted time: #{time_str} -> #{time}")
        time
      _ ->
        IO.puts("⚠️ Could not extract time from title: #{product_title}")
        ~T[19:00:00] # Default time if not found
    end

    # Extract price (if available)
    entry_fee_cents = cond do
      # Try omnibus data first (most reliable)
      !Enum.empty?(omnibus_divs) ->
        price_text = List.first(omnibus_divs)
        {price, _} = Float.parse(price_text)
        cents = round(price * 100)
        IO.puts("Extracted price from omnibus data: #{price_text} -> #{cents} cents")
        cents

      # Then try price spans
      !Enum.empty?(price_texts) ->
        price_text = List.first(price_texts)
        # Convert price like "15,00" to cents (1500)
        price_text
        |> String.replace(",", ".")
        |> Float.parse()
        |> case do
          {price, _} ->
            cents = round(price * 100)
            IO.puts("Extracted price: #{price_text} -> #{cents} cents")
            cents
          :error ->
            IO.puts("⚠️ Could not parse price: #{price_text}")
            0
        end

      # Default if no price found
      true ->
        IO.puts("⚠️ No price found on page")
        1500 # Default to 15 zł (typical price for these events)
    end

    IO.puts("Event details extracted - Day: #{day_of_week}, Time: #{start_time}, Price: #{entry_fee_cents} cents")
    {day_of_week, start_time, entry_fee_cents}
  end
end

# Process each venue URL
Enum.each(venue_urls, fn url ->
  IO.puts("\n\n=== Testing URL: #{url} ===\n")

  case HTTPoison.get(url, [], follow_redirect: true) do
    {:ok, %{status_code: 200, body: body}} ->
      {day, time, fee} = extract_event_details.(body)
      IO.puts("\nRESULT: Day: #{day}, Time: #{time}, Fee: #{fee}")

    {:ok, %{status_code: status}} ->
      IO.puts("Failed with status code: #{status}")

    {:error, error} ->
      IO.puts("Error: #{inspect(error)}")
  end
end)

IO.puts("\nTest completed")
