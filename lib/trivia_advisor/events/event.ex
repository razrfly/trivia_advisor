defmodule TriviaAdvisor.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Locations.{Venue, City}
  require Logger
  use Waffle.Ecto.Schema

  schema "events" do
    field :name, :string
    field :day_of_week, :integer
    field :start_time, :time
    field :frequency, Ecto.Enum, values: [:weekly, :biweekly, :monthly, :irregular]
    field :entry_fee_cents, :integer
    field :description, :string
    field :hero_image, TriviaAdvisor.Uploaders.HeroImage.Type

    belongs_to :venue, Venue
    has_many :event_sources, TriviaAdvisor.Events.EventSource, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :venue_id, :day_of_week, :start_time, :frequency,
                   :entry_fee_cents, :description])
    |> cast_attachments(attrs, [:hero_image])
    |> validate_required([:venue_id, :day_of_week, :start_time, :frequency])
    |> validate_inclusion(:day_of_week, 1..7)
    |> foreign_key_constraint(:venue_id)
  end

  @doc """
  Parses frequency text into the correct enum value.
  For tests:
  - Handles "every week" and similar variations
  - Returns :irregular for empty/nil/random text

  Note: In production, frequency is determined by event_store.ex
  which defaults everything to weekly unless explicitly stated otherwise.
  """
  def parse_frequency(nil), do: :irregular  # Test compatibility
  def parse_frequency(""), do: :irregular   # Test compatibility
  def parse_frequency(text) when is_binary(text) do
    text = String.trim(text) |> String.downcase()
    cond do
      # Bi-weekly patterns
      String.contains?(text, ["bi-weekly", "biweekly", "fortnightly"]) or
      Regex.match?(~r/\bevery\s+(?:2|two)\s+weeks?\b/, text) ->
        :biweekly

      # Monthly patterns
      String.contains?(text, ["monthly", "every month"]) or
      (String.contains?(text, ["last", "first", "second", "third", "fourth"]) and
       String.contains?(text, ["of the month", "of every month"])) ->
        :monthly

      # Weekly patterns - handle test cases
      String.contains?(text, ["every week", "weekly", "each week"]) ->
        :weekly

      # Random text is irregular (test compatibility)
      true ->
        :irregular
    end
  end
  def parse_frequency(_), do: :irregular  # Test compatibility

  @doc """
  Parses currency strings into cents integer based on venue's country.
  Returns nil for free events or unparseable amounts.
  Raises if venue structure is invalid.
  """
  def parse_currency(nil, _venue), do: nil
  def parse_currency(amount, _venue) when is_integer(amount), do: amount
  def parse_currency(amount, venue) when is_binary(amount) do
    amount = String.trim(amount)

    cond do
      Regex.match?(~r/free|no charge/i, amount) ->
        nil

      true ->
        _currency = get_currency_for_venue!(venue)
        case extract_amount(amount) do
          {:ok, number} ->
            value =
              number
              |> Float.to_string()
              |> Decimal.new()
              |> Decimal.mult(Decimal.new(100))
              |> Decimal.to_integer()
            value
          :error ->
            Logger.warning("Failed to parse price: #{amount}")
            nil
        end
    end
  end

  @doc """
  Gets the currency code for a venue by following venue -> city -> country relationship.
  Raises if city or country information is missing.
  """
  def get_currency_for_venue!(%Venue{city: %City{country: nil}} = _venue), do:
    raise "Venue's city must have an associated country"

  def get_currency_for_venue!(%Venue{city: %City{country: %{code: code}}} = _venue) when not is_nil(code) do
    case Countries.get(code) do
      nil ->
        raise "Invalid country code: #{code}"
      country_data ->
        country_data.currency_code
    end
  end

  def get_currency_for_venue!(%Venue{city: nil}), do:
    raise "Venue must have an associated city"

  def get_currency_for_venue!(%Venue{} = _venue), do:
    raise "Venue's city association is not loaded"

  # Private helper to safely extract numeric amount
  defp extract_amount(amount) do
    # First try with currency symbol - allow whitespace between symbol and number
    case Regex.run(~r/^([£€$])\s*(\d+(?:\.\d{2})?)\s*$/u, amount) do
      [_, _symbol, number] ->
        parse_number(number)
      nil ->
        # Then try just the number
        case Regex.run(~r/^\s*(\d+(?:\.\d{2})?)\s*$/, amount) do
          [_, number] -> parse_number(number)
          nil -> :error
        end
    end
  end

  defp parse_number(number) do
    case Float.parse(number) do
      {amount, _} when amount >= 0 -> {:ok, amount}
      _ -> :error
    end
  end
end
