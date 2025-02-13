defmodule TriviaAdvisor.Events.Event do
  use Ecto.Schema
  import Ecto.Changeset
  alias TriviaAdvisor.Locations.{Venue, City}
  require Logger

  @frequencies ~w(weekly biweekly monthly irregular)a

  schema "events" do
    field :name, :string
    field :day_of_week, :integer
    field :start_time, :time
    field :frequency, Ecto.Enum, values: @frequencies, default: :weekly
    field :entry_fee_cents, :integer
    field :description, :string

    belongs_to :venue, TriviaAdvisor.Locations.Venue
    has_many :event_sources, TriviaAdvisor.Events.EventSource, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:name, :day_of_week, :start_time, :frequency, :entry_fee_cents, :description, :venue_id])
    |> validate_required([:day_of_week, :start_time, :frequency, :venue_id])
    |> validate_entry_fee()
  end

  @doc """
  Parses frequency text into the correct enum value.
  """
  def parse_frequency(text) when is_binary(text) do
    text = String.trim(text) |> String.downcase()
    cond do
      text == "" -> :irregular
      Regex.match?(~r/\b(every\s+2\s+weeks?|bi-?weekly|fortnightly)\b/, text) -> :biweekly
      Regex.match?(~r/\b(every\s+week|weekly|each\s+week)\b/, text) -> :weekly
      Regex.match?(~r/\b(every\s+month|monthly)\b/, text) -> :monthly
      true -> :irregular
    end
  end
  def parse_frequency(_), do: :irregular
  @doc """
  Parses currency strings into cents integer based on venue's country.
  Returns nil for free events or unparseable amounts.
  Raises if venue structure is invalid.

  ## Examples
      iex> parse_currency("£3.50", venue_with_gb)
      350
      iex> parse_currency("3.50", venue_with_gb)  # Uses GB currency
      350
      iex> parse_currency("Free", venue_with_de)
      nil
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
            # Convert float to string first to handle decimal numbers correctly
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

  defp validate_entry_fee(changeset) do
    case get_field(changeset, :entry_fee_cents) do
      nil -> changeset
      amount when is_integer(amount) and amount >= 0 -> changeset
      _ -> add_error(changeset, :entry_fee_cents, "must be a non-negative integer or nil")
    end
  end
end
