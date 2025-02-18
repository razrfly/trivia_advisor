defmodule TriviaAdvisor.Scraping.GoogleLookupTest do
  use TriviaAdvisor.DataCase
  alias TriviaAdvisor.Scraping.GoogleLookup
  import ExUnit.CaptureLog

  import Mox
  setup :verify_on_exit!

  setup do
    System.put_env("GOOGLE_MAPS_API_KEY", "test_api_key")
    on_exit(fn -> System.delete_env("GOOGLE_MAPS_API_KEY") end)
    :ok
  end

  describe "lookup_address/1 with business" do
    test "returns full business details when found in Places API" do
      # Mock Places API findplacefromtext response
      places_search_response = %{
        "status" => "OK",
        "candidates" => [%{
          "place_id" => "ChIJuQdxBb1w2EcRvnxVeL5abUw",
          "types" => ["bar", "restaurant", "food", "point_of_interest", "establishment"]
        }]
      }

      # Mock Places API details response
      place_details_response = %{
        "status" => "OK",
        "result" => %{
          "name" => "The Eagle",
          "place_id" => "ChIJuQdxBb1w2EcRvnxVeL5abUw",
          "formatted_address" => "Bene't St, Cambridge CB2 3QN, UK",
          "geometry" => %{
            "location" => %{"lat" => 52.2039937, "lng" => 0.1180895}
          },
          "international_phone_number" => "+44 1223 505020",
          "website" => "https://www.greeneking.co.uk/pubs/cambridgeshire/eagle",
          "url" => "https://maps.google.com/?cid=5507157693453139134",
          "types" => ["bar", "restaurant", "food", "point_of_interest", "establishment"],
          "rating" => 4.4,
          "user_ratings_total" => 6714,
          "opening_hours" => %{
            "periods" => [
              %{"close" => %{"day" => 0, "time" => "2230"}, "open" => %{"day" => 0, "time" => "1200"}}
            ],
            "weekday_text" => ["Monday: 12:00–11:00 PM"]
          }
        }
      }

      # Mock Geocoding API response
      geocoding_response = %{
        "status" => "OK",
        "results" => [%{
          "formatted_address" => "Bene't St, Cambridge CB2 3QN, UK",
          "geometry" => %{
            "location" => %{"lat" => 52.2039937, "lng" => 0.1180895}
          },
          "address_components" => [
            %{"long_name" => "Cambridge", "short_name" => "Cambridge", "types" => ["locality"]},
            %{"long_name" => "England", "short_name" => "England", "types" => ["administrative_area_level_1"]},
            %{"long_name" => "United Kingdom", "short_name" => "GB", "types" => ["country"]},
            %{"long_name" => "CB2 3QN", "short_name" => "CB2 3QN", "types" => ["postal_code"]}
          ]
        }]
      }

      # Set up mock HTTP responses
      expect(HTTPoison.Mock, :get, 3, fn url, [], [follow_redirect: true] ->
        cond do
          String.contains?(url, "findplacefromtext") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(places_search_response)}}
          String.contains?(url, "place/details") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(place_details_response)}}
          String.contains?(url, "geocode") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(geocoding_response)}}
        end
      end)

      # Temporarily set logger level to :info for this test
      Logger.configure(level: :info)
      log = capture_log(fn ->
        assert {:ok, result} = GoogleLookup.lookup_address("The Eagle Pub, Cambridge, UK", venue_name: "The Eagle")
        assert result["place_id"] == "ChIJuQdxBb1w2EcRvnxVeL5abUw"
        assert result["name"] == "The Eagle"
        assert result["phone"] == "+44 1223 505020"
        assert result["city"]["name"] == "Cambridge"
        assert result["country"]["code"] == "GB"
        assert result["rating"]["value"] == 4.4
      end)
      Logger.configure(level: :warning) # Reset back to warning

      assert log =~ "📡 Querying Google Maps API"
      assert log =~ "✅ Found business details for The Eagle"
    end

    test "skips API call for existing venue" do
      Logger.configure(level: :info)
      log = capture_log(fn ->
        assert {:ok, result} = GoogleLookup.lookup_address("The Eagle Pub, Cambridge, UK",
          venue_name: "The Eagle",
          existing_coordinates: {52.2039937, 0.1180895}  # Use existing coordinates
        )

        # Verify the response structure
        assert result["name"] == "The Eagle"
        assert result["geometry"]["location"]["lat"] == 52.2039937
        assert result["geometry"]["location"]["lng"] == 0.1180895
        assert result["cached"] == true
      end)
      Logger.configure(level: :warning)

      assert log =~ "⏭️ Using existing coordinates for venue: The Eagle"
    end
  end

  describe "lookup_address/1 with street address" do
    test "returns address details without business info for non-business address" do
      # Mock Places API findplacefromtext response (street address)
      places_search_response = %{
        "status" => "OK",
        "candidates" => [%{
          "place_id" => "EiAyOTUgVyBFbmQgTG4sIExvbmRvbiBOVzYgMUxHLCBVSyIxEi8KFAoSCaduyS55EHZIEdRx3ILM5hdHEKcCKhQKEglZztR3dxB2SBHdvRogaqaMYg",
          "types" => ["street_address"]
        }]
      }

      # Mock Geocoding API response
      geocoding_response = %{
        "status" => "OK",
        "results" => [%{
          "formatted_address" => "295 W End Ln, London NW6 1LG, UK",
          "geometry" => %{
            "location" => %{"lat" => 51.5513213, "lng" => -0.1917062}
          },
          "address_components" => [
            %{"long_name" => "London", "short_name" => "London", "types" => ["locality"]},
            %{"long_name" => "England", "short_name" => "England", "types" => ["administrative_area_level_1"]},
            %{"long_name" => "United Kingdom", "short_name" => "GB", "types" => ["country"]},
            %{"long_name" => "NW6 1LG", "short_name" => "NW6 1LG", "types" => ["postal_code"]}
          ]
        }]
      }

      # Set up mock HTTP responses
      expect(HTTPoison.Mock, :get, 2, fn url, [], [follow_redirect: true] ->
        cond do
          String.contains?(url, "findplacefromtext") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(places_search_response)}}
          String.contains?(url, "geocode") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(geocoding_response)}}
        end
      end)

      Logger.configure(level: :info)
      log = capture_log(fn ->
        assert {:ok, result} = GoogleLookup.lookup_address("295 West End Lane, London NW6 1LG, UK")
        assert result["place_id"] == nil
        assert result["name"] == "295 W End Ln"
        assert result["formatted_address"] == "295 W End Ln, London NW6 1LG, UK"
        assert result["city"]["name"] == "London"
        assert result["country"]["code"] == "GB"
        assert result["phone"] == nil
        assert result["rating"] == nil
        assert result["types"] == ["street_address"]
      end)
      Logger.configure(level: :warning)

      assert log =~ "📡 Using Geocoding API"
      assert log =~ "✅ Found address details"
    end
  end

  describe "error handling" do
    test "handles missing API key" do
      System.delete_env("GOOGLE_MAPS_API_KEY")

      log = capture_log(fn ->
        assert {:error, :missing_api_key} = GoogleLookup.lookup_address("test")
      end)

      assert log =~ "❌ Critical error: Missing Google Maps API key"
    end

    test "handles missing required data" do
      log = capture_log(fn ->
        assert {:error, :missing_address} = GoogleLookup.lookup_address("")
      end)

      assert log =~ "❌ Critical error: Missing required address"
    end
  end
end
