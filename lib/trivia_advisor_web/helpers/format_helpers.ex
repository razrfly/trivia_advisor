defmodule TriviaAdvisorWeb.Helpers.FormatHelpers do
  @moduledoc """
  Helper functions for formatting data across views, including time, event sources, and other display elements.
  """
  import Calendar, only: [strftime: 2]

  # Time formatting helpers

  @doc """
  Formats a datetime into relative time words (e.g., "5 minutes ago").

  ## Examples

      iex> time_ago(~U[2023-01-01 00:00:00Z])
      "1 year ago"

  Returns string with relative time description or nil for invalid inputs.
  """
  def time_ago(datetime) when is_struct(datetime) do
    case Timex.format(datetime, "{relative}", :relative) do
      {:ok, relative_time} -> relative_time
      {:error, _reason} -> nil
    end
  end
  def time_ago(_), do: nil

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
    case Timex.format(datetime, "{relative}", :relative) do
      {:ok, relative_time} -> relative_time
      {:error, _reason} -> "recently"
    end
  end
  def time_ago_in_words(_), do: "recently"

  @doc """
  Formats a date to a friendly month and day format (e.g., "Jan 15").

  ## Examples

      iex> format_month_day(~D[2023-01-15])
      "Jan 15"
  """
  def format_month_day(date) when is_struct(date) do
    month = case date.month do
      1 -> "Jan"
      2 -> "Feb"
      3 -> "Mar"
      4 -> "Apr"
      5 -> "May"
      6 -> "Jun"
      7 -> "Jul"
      8 -> "Aug"
      9 -> "Sep"
      10 -> "Oct"
      11 -> "Nov"
      12 -> "Dec"
    end

    "#{month} #{date.day}"
  end
  def format_month_day(_), do: "Unknown date"

  @doc """
  Formats a day of week integer into full day name.

  ## Examples

      iex> format_day_of_week(1)
      "Monday"
  """
  def format_day_of_week(day) when is_integer(day) do
    case day do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      7 -> "Sunday"
      _ -> "Unknown"
    end
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

  ## Examples

      iex> format_active_since(venue)
      "January 2023"
  """
  def format_active_since(venue) do
    if venue.events && Enum.any?(venue.events) do
      event = hd(venue.events)
      if event.inserted_at do
        # Format as Month Year (e.g., "January 2023")
        strftime(event.inserted_at, "%B %Y")
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
    string
    |> String.split(" ")
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
