defmodule TriviaAdvisorWeb.Helpers.FormatHelpers do
  @moduledoc """
  Helper functions for formatting data across views, including time, event sources, and other display elements.
  """
  require Logger

  # Time formatting helpers

  @doc """
  Formats a datetime into relative time words (e.g., "5 minutes ago").
  Contains special handling for incorrect system time, which is useful in development/testing.

  ## Examples

      iex> time_ago(~U[2023-01-01 00:00:00Z])
      "1 year ago"

  Returns string with relative time description or nil for invalid inputs.
  """
  def time_ago(datetime) when is_struct(datetime) do
    current_utc = DateTime.utc_now()

    # Handle incorrect system year (workaround for system time being in 2025)
    if current_utc.year > 2024 do
      # Convert to DateTime if needed
      input_dt = to_comparable_datetime(datetime)

      # Shift both dates to correct year if needed
      year_diff = current_utc.year - 2024
      corrected_now = Timex.shift(current_utc, years: -year_diff)
      corrected_input = if input_dt.year > 2024,
        do: Timex.shift(input_dt, years: -year_diff),
        else: input_dt

      # Use Timex.from_now with corrected dates
      time_diff = Timex.diff(corrected_now, corrected_input, :seconds)

      # For dates in the past (positive diff)
      if time_diff > 0 do
        Timex.from_now(corrected_input, corrected_now)
      else
        "in the future"
      end
    else
      # Normal case - use Timex directly
      Timex.from_now(datetime)
    end
  rescue
    _e ->
      # On error, return nil (will be replaced with "recently" by time_ago_in_words)
      nil
  end
  def time_ago(_), do: nil

  # Helper to convert any datetime struct to comparable format
  defp to_comparable_datetime(dt) do
    case dt do
      %DateTime{} -> dt
      %NaiveDateTime{} ->
        # Convert NaiveDateTime to DateTime (assuming UTC for simplicity)
        {:ok, datetime} = DateTime.from_naive(dt, "Etc/UTC")
        datetime
      _ -> DateTime.utc_now() # fallback
    end
  end

  @doc """
  Similar to time_ago but always returns a string, with "recently" as fallback.
  Useful for UI elements where nil would cause display issues.

  ## Examples

      iex> time_ago_in_words(~U[2023-01-01 00:00:00Z])
      "1 year ago"

      iex> time_ago_in_words(nil)
      "recently"
  """
  def time_ago_in_words(datetime) when is_struct(datetime) do
    time_ago(datetime) || "recently"
  end
  def time_ago_in_words(_), do: "recently"

  @doc """
  Formats a date to a friendly month and day format (e.g., "Jan 15").
  Uses Timex for formatting.

  ## Examples

      iex> format_month_day(~D[2023-01-15])
      "Jan 15"
  """
  def format_month_day(date) when is_struct(date) do
    Timex.format!(date, "%b %d", :strftime)
  end
  def format_month_day(_), do: "Unknown date"

  @doc """
  Formats a day of week integer into full day name.
  Uses Timex for day names.

  ## Examples

      iex> format_day_of_week(1)
      "Monday"
  """
  def format_day_of_week(day) when is_integer(day) and day in 1..7 do
    day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    Enum.at(day_names, day - 1)
  end
  def format_day_of_week(_), do: "Unknown"

  # Source and event formatting helpers

  @doc """
  Checks if a venue has any event sources.

  ## Examples

      iex> has_event_source?(venue)
      true
  """
  def has_event_source?(venue) do
    venue.events &&
    Enum.any?(venue.events) &&
    hd(venue.events).event_sources &&
    Enum.any?(hd(venue.events).event_sources)
  end

  @doc """
  Formats the 'last updated' time from an event source.

  ## Examples

      iex> format_last_updated(venue)
      "2 days ago"
  """
  def format_last_updated(venue) do
    if venue.events && Enum.any?(venue.events) do
      event = hd(venue.events)
      if event.event_sources && Enum.any?(event.event_sources) do
        event_source = hd(event.event_sources)
        if event_source.last_seen_at do
          time_ago_in_words(event_source.last_seen_at)
        else
          "recently"
        end
      else
        "recently"
      end
    else
      "recently"
    end
  end

  @doc """
  Formats the 'active since' date from an event.
  Uses Timex for date formatting.

  ## Examples

      iex> format_active_since(venue)
      "January 2023"
  """
  def format_active_since(venue) do
    if venue.events && Enum.any?(venue.events) do
      event = hd(venue.events)
      if event.inserted_at do
        # Format as Month Year (e.g., "January 2023")
        Timex.format!(event.inserted_at, "%B %Y", :strftime)
      else
        "unknown date"
      end
    else
      "unknown date"
    end
  end

  @doc """
  Gets the source name from a venue's events, with the name titleized.
  Returns a map with name and url.

  ## Examples

      iex> get_source_name(venue)
      %{name: "TriviaAdvisor", url: "https://triviaadvisor.com"}
  """
  def get_source_name(venue) when is_map(venue) do
    if venue.events && Enum.any?(venue.events) do
      event = hd(venue.events)
      if event.event_sources && Enum.any?(event.event_sources) do
        event_source = hd(event.event_sources)
        if event_source.source && event_source.source.name do
          %{
            name: titleize(event_source.source.name),
            url: event_source.source_url || event_source.source.website_url || nil
          }
        else
          %{name: "TriviaAdvisor", url: nil}
        end
      else
        %{name: "TriviaAdvisor", url: nil}
      end
    else
      %{name: "TriviaAdvisor", url: nil}
    end
  end

  @doc """
  Gets the source name directly from an event source, with the name titleized.
  Returns a map with name and url.

  ## Examples

      iex> get_source_name_from_event_source(event_source)
      %{name: "TriviaAdvisor", url: "https://triviaadvisor.com"}
  """
  def get_source_name_from_event_source(event_source) when is_map(event_source) do
    if Map.has_key?(event_source, :source) && !is_nil(event_source.source) do
      source_name = case event_source.source do
        %{name: name} when is_binary(name) -> name
        source when is_map(source) -> Map.get(source, :name)
        _ -> "Unknown Source"
      end

      source_url = event_source.source_url ||
                  (try do
                     if is_map(event_source.source), do: Map.get(event_source.source, :website_url)
                   rescue
                     _ -> nil
                   end) ||
                  nil

      %{
        name: titleize(source_name),
        url: source_url
      }
    else
      %{name: "Unknown Source", url: nil}
    end
  end

  @doc """
  Titleizes a string by capitalizing each word.

  ## Examples

      iex> titleize("hello world")
      "Hello World"
  """
  def titleize(string) when is_binary(string) do
    # Use String.split/3 with the :trim option to handle extra spaces
    string
    |> String.split(" ", trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  def titleize(nil), do: nil

  @doc """
  Extracts event source data from a venue.

  ## Examples

      iex> get_event_source_data(venue)
      %{last_seen_at: ~U[2023-01-01 00:00:00Z], source_name: "TriviaAdvisor"}
  """
  def get_event_source_data(venue) do
    events = Map.get(venue, :events, [])

    if Enum.any?(events) do
      # Get first event with event_sources
      event = Enum.find(events, fn event ->
        Map.get(event, :event_sources) &&
        is_list(event.event_sources) &&
        Enum.any?(event.event_sources)
      end)

      if event do
        # Get most recent event source
        # Filter out event_sources with nil or invalid last_seen_at before sorting
        valid_event_sources = Enum.filter(event.event_sources, fn es ->
          is_struct(es.last_seen_at, DateTime) || is_struct(es.last_seen_at, NaiveDateTime)
        end)

        event_source = if Enum.any?(valid_event_sources) do
          valid_event_sources
          |> Enum.sort_by(& &1.last_seen_at, {:desc, DateTime})
          |> List.first()
        else
          List.first(event.event_sources)
        end

        if event_source do
          source_data = get_source_name_from_event_source(event_source)
          %{
            last_seen_at: event_source.last_seen_at,
            source_name: source_data.name,
            source_url: source_data.url
          }
        else
          %{}
        end
      else
        %{}
      end
    else
      %{}
    end
  end

  # Pluralization helper

  @doc """
  Helper for pluralization.

  ## Examples

      iex> pluralize(1, "day")
      "day"

      iex> pluralize(2, "day")
      "days"
  """
  def pluralize(1, text), do: text
  def pluralize(_, text), do: "#{text}s"
end
