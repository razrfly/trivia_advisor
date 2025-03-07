defmodule TriviaAdvisor.Locations.Oban.DailyRecalibrateWorkerTest do
  use TriviaAdvisor.DataCase, async: true

  alias TriviaAdvisor.Locations.Oban.DailyRecalibrateWorker
  alias TriviaAdvisor.Locations.{City, Venue}
  alias TriviaAdvisor.Repo

  describe "perform/1" do
    test "updates city coordinates based on venue locations" do
      # Create test country
      {:ok, country} = %TriviaAdvisor.Locations.Country{
        name: "Test Country",
        code: "TC"
      } |> Repo.insert()

      # Create test city with no coordinates using changeset
      {:ok, city} = %City{}
        |> City.changeset(%{
          name: "Test City",
          country_id: country.id,
          latitude: nil,
          longitude: nil
        })
        |> Repo.insert()

      # Create test venues with coordinates
      venues = [
        %{latitude: 10.0, longitude: 20.0},
        %{latitude: 12.0, longitude: 22.0},
        %{latitude: 14.0, longitude: 24.0}
      ]

      # Insert test venues using changeset
      Enum.each(venues, fn coords ->
        %Venue{}
        |> Venue.changeset(%{
          name: "Test Venue #{coords.latitude}",
          address: "#{coords.latitude} Test Street",
          city_id: city.id,
          latitude: coords.latitude,
          longitude: coords.longitude
        })
        |> Repo.insert!()
      end)

      # Run the worker
      assert :ok = DailyRecalibrateWorker.perform(%Oban.Job{id: 1})

      # Fetch the updated city
      updated_city = Repo.get(City, city.id)

      # Expected coordinates (average of venue coordinates)
      expected_lat = 12.0
      expected_lng = 22.0

      # Assert coordinates were updated correctly
      assert updated_city.latitude
      assert updated_city.longitude
      assert Decimal.to_float(updated_city.latitude) == expected_lat
      assert Decimal.to_float(updated_city.longitude) == expected_lng
    end

    test "handles cities with no venues gracefully" do
      # Create test country
      {:ok, country} = %TriviaAdvisor.Locations.Country{
        name: "Test Country",
        code: "TC"
      } |> Repo.insert()

      # Create test city with no coordinates and no venues using changeset
      {:ok, city} = %City{}
        |> City.changeset(%{
          name: "Empty City",
          country_id: country.id,
          latitude: nil,
          longitude: nil
        })
        |> Repo.insert()

      # Run the worker
      assert :ok = DailyRecalibrateWorker.perform(%Oban.Job{id: 2})

      # Fetch the city - coordinates should still be nil
      updated_city = Repo.get(City, city.id)
      assert updated_city.latitude == nil
      assert updated_city.longitude == nil
    end
  end
end
