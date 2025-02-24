defmodule TriviaAdvisor.Scraping.Helpers.VenueHelpers do
  @moduledoc """
  Generic helper functions for venue data extraction across different scrapers.
  """

  require Logger
  alias TriviaAdvisor.Scraping.Helpers.TimeParser

  @doc """
  Parses day of week from time text into integer (1-7, Monday-Sunday).
  """
  def parse_day_of_week(time_text) do
    case TimeParser.parse_day_of_week(time_text) do
      {:ok, day} -> day
      {:error, reason} -> raise reason
    end
  end

  @doc """
  Parses time string into Time struct.
  """
  def parse_time(time_text) do
    case TimeParser.parse_time(time_text) do
      {:ok, time_str} -> Time.from_iso8601!(time_str <> ":00")
      {:error, reason} -> raise reason
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
  def log_venue_details(venue_data) do
    Logger.info("""
    📍 Extracted Venue Details:
      Title (Raw)   : #{inspect(venue_data.raw_title)}
      Title (Clean) : #{inspect(venue_data.title)}
      Address       : #{venue_data.address}
      Time Text     : #{venue_data.time_text}
      Day of Week   : #{venue_data.day_of_week}
      Start Time    : #{venue_data.start_time}
      Frequency     : #{venue_data.frequency}
      Fee          : #{venue_data.fee_text}
      Phone        : #{venue_data.phone}
      Website      : #{venue_data.website}
      Description  : #{String.slice(venue_data.description || "", 0..100)}...
      Hero Image   : #{venue_data.hero_image_url}
      Source URL   : #{venue_data.url}
      Facebook     : #{venue_data.facebook}
      Instagram    : #{venue_data.instagram}#{format_performer(Map.get(venue_data, :performer))}
    """)
  end

  defp format_performer(nil), do: ""
  defp format_performer(performer) do
    """

      Performer     : #{performer.name}
      Profile Image: #{performer.profile_image}
    """
  end
end
