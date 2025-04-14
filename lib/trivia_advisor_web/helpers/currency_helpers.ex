defmodule TriviaAdvisorWeb.Helpers.CurrencyHelpers do
  @moduledoc """
  Helper functions for formatting currencies across views.
  """
  require Logger

  @doc """
  Formats an amount in cents to a proper currency string using the Money library.
  Takes the amount in cents and a currency code.

  ## Examples

      iex> format_currency(1000, "USD")
      "$10.00"

      iex> format_currency(1000, "GBP")
      "£10.00"

      iex> format_currency(nil, "USD")
      "Free"
  """
  def format_currency(amount_cents, currency_code) when is_number(amount_cents) do
    # Create Money struct with proper currency
    money = Money.new(amount_cents, currency_code)

    # Let the Money library handle the formatting
    Money.to_string(money)
  end
  def format_currency(_, _), do: "Free"

  @doc """
  Gets the appropriate currency code for a venue based on its country.
  Tries to extract the country code from the venue's associations.

  ## Examples

      iex> get_country_currency(%{country_code: "GB"})
      "GBP"

      iex> get_country_currency(%{city: %{country: %{code: "AU"}}})
      "AUD"
  """
  def get_country_currency(venue) do
    country = get_country(venue)

    cond do
      # Check if currency code is stored in country data
      country && Map.has_key?(country, :currency_code) && country.currency_code ->
        country.currency_code
      # Use Countries library to get currency code if we have a country code
      country && country.code ->
        country_data = Countries.get(country.code)
        if country_data && Map.has_key?(country_data, :currency_code), do: country_data.currency_code, else: "USD"
      # Default to USD if we don't know
      true ->
        "USD"
    end
  end

  @doc """
  Helper to get country information from a venue.
  Tries multiple paths to find the country data.

  Returns a map with at least the country code.
  """
  def get_country(venue) do
    # First check if venue has a direct country_code
    if Map.has_key?(venue, :country_code) do
      %{code: venue.country_code, name: "Unknown", slug: "unknown"}
    else
      # Try to safely extract country from city if it exists
      try do
        if Map.has_key?(venue, :city) &&
           !is_nil(venue.city) &&
           !is_struct(venue.city, Ecto.Association.NotLoaded) &&
           Map.has_key?(venue.city, :country) &&
           !is_nil(venue.city.country) &&
           !is_struct(venue.city.country, Ecto.Association.NotLoaded) do
          venue.city.country
        else
          # Default fallback
          %{code: "US", name: "Unknown", slug: "unknown"}
        end
      rescue
        # If any error occurs, return a default
        _ -> %{code: "US", name: "Unknown", slug: "unknown"}
      end
    end
  end

  @doc """
  Ensures a venue has proper country data by using city's country if necessary.
  """
  def ensure_country_data(venue, city) do
    # If venue already has complete country data, return as is
    if venue.city && !is_struct(venue.city.country, Ecto.Association.NotLoaded) do
      venue
    else
      # Try to use city's country data
      try do
        # Use the put_in function to update the venue.city with the provided city
        # This will make city.country available for country code detection
        put_in(venue.city, city)
      rescue
        # If any error occurs (like path doesn't exist), return original venue
        _ -> venue
      end
    end
  end
end
