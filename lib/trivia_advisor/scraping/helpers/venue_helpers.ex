defmodule TriviaAdvisor.Scraping.Helpers.VenueHelpers do
  @moduledoc """
  Generic helper functions for venue data extraction across different scrapers.
  """

  require Logger

  @doc """
  Parses day of week from time text into integer (1-7, Monday-Sunday).
  """
  def parse_day_of_week(time_text) do
    cond do
      String.contains?(time_text, "Monday") -> 1
      String.contains?(time_text, "Tuesday") -> 2
      String.contains?(time_text, "Wednesday") -> 3
      String.contains?(time_text, "Thursday") -> 4
      String.contains?(time_text, "Friday") -> 5
      String.contains?(time_text, "Saturday") -> 6
      String.contains?(time_text, "Sunday") -> 7
      true -> raise "Invalid day in time_text: #{time_text}"
    end
  end

  @doc """
  Parses time string into Time struct.
  """
  def parse_time(time_text) do
    case Regex.run(~r/(\d{1,2}[:.]?\d{2})/, time_text) do
      [_, time] ->
        time
        |> String.replace(".", ":")
        |> String.pad_leading(5, "0")
        |> then(fn t -> t <> ":00" end)
        |> Time.from_iso8601!()
      nil -> raise "Could not parse time from: #{time_text}"
    end
  end

  @doc """
  Downloads an image from a URL and saves it to a temporary file.
  Returns {:ok, %{path: path, file_name: name}} or {:error, reason}
  """
  def download_image(nil), do: {:error, :no_image}
  def download_image(url) do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        tmp_path = Path.join(System.tmp_dir!(), "#{:crypto.strong_rand_bytes(16) |> Base.encode16()}")
        File.write!(tmp_path, body)
        {:ok, %{
          path: tmp_path,
          file_name: Path.basename(url)
        }}
      _ ->
        {:error, :download_failed}
    end
  end

  @doc """
  Logs extracted venue details in a consistent format.
  """
  def log_venue_details(venue) do
    Logger.info("""
    📍 Extracted Venue Details:
      Title (Raw)   : #{inspect(venue.raw_title)}
      Title (Clean) : #{inspect(venue.title)}
      Address       : #{inspect(venue.address)}
      Time Text     : #{inspect(venue.time_text)}
      Day of Week   : #{inspect(venue.day_of_week)}
      Start Time    : #{inspect(venue.start_time)}
      Frequency     : #{inspect(venue.frequency)}
      Fee          : #{inspect(venue.fee_text)}
      Phone        : #{inspect(venue.phone || "Not provided")}
      Website      : #{inspect(venue.website || "Not provided")}
      Description  : #{inspect(String.slice(venue.description || "", 0..100))}...
      Hero Image   : #{inspect(venue.hero_image_url || "Not provided")}
      Source URL   : #{inspect(venue.url)}
    """)
  end
end
