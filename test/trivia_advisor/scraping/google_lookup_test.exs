defmodule TriviaAdvisor.Scraping.GoogleLookupTest do
  use TriviaAdvisor.DataCase
  alias TriviaAdvisor.Scraping.GoogleLookup

  import Mox
  setup :verify_on_exit!

  @mock_api_key "test_api_key"

  setup do
    Application.put_env(:trivia_advisor, :google_api_key, @mock_api_key)
    :ok
  end

  describe "lookup_address/1" do
    test "returns enriched place data with country and city" do
      mock_places_response = %{
        "status" => "OK",
        "candidates" => [
          %{
            "name" => "Madison Square Garden",
            "formatted_address" => "4 Pennsylvania Plaza, New York, NY 10001, USA",
            "place_id" => "ChIJhRwB-yFawokR5Phil-QQ3zM",
            "geometry" => %{
              "location" => %{"lat" => 40.7505, "lng" => -73.9934}
            },
            "address_components" => [
              %{
                "long_name" => "United States",
                "short_name" => "US",
                "types" => ["country"]
              },
              %{
                "long_name" => "New York",
                "short_name" => "NY",
                "types" => ["locality"]
              }
            ]
          }
        ]
      }

      expect(HTTPoison.Mock, :get, fn _url, [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_places_response)}}
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Madison Square Garden")
      assert result["name"] == "Madison Square Garden"
      assert result["country"]["code"] == "US"
      assert result["city"]["name"] == "New York"
    end

    test "handles geocoding fallback with location components" do
      places_response = %{
        "status" => "OK",
        "candidates" => []
      }

      geocoding_response = %{
        "status" => "OK",
        "results" => [%{
          "formatted_address" => "1600 Amphitheatre Parkway, Mountain View, CA 94043",
          "geometry" => %{
            "location" => %{"lat" => 37.4224764, "lng" => -122.0842499}
          },
          "address_components" => [
            %{
              "long_name" => "Mountain View",
              "short_name" => "MV",
              "types" => ["locality", "political"]
            },
            %{
              "long_name" => "United States",
              "short_name" => "US",
              "types" => ["country", "political"]
            }
          ]
        }]
      }

      expect(HTTPoison.Mock, :get, 2, fn url, [], [follow_redirect: true] ->
        if String.contains?(url, "place/findplacefromtext") do
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(places_response)}}
        else
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(geocoding_response)}}
        end
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Google HQ")
      assert result["country"]["name"] == "United States"
      assert result["city"]["name"] == "Mountain View"
    end
  end

  describe "location components" do
    test "handles missing address components gracefully" do
      mock_response = %{
        "status" => "OK",
        "candidates" => [%{
          "place_id" => "test_place_id",
          "formatted_address" => "Unknown Location",
          "name" => "Test Place",
          "address_components" => []
        }]
      }

      expect(HTTPoison.Mock, :get, 2, fn url, [], [follow_redirect: true] ->
        cond do
          String.contains?(url, "place/findplacefromtext") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(mock_response)}}
          String.contains?(url, "geocode") ->
            {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{
              "status" => "OK",
              "results" => []
            })}}
        end
      end)

      assert {:error, :no_results} = GoogleLookup.lookup_address("Test Place")
    end

    test "geocoding filters by locality result type" do
      places_response = %{
        "status" => "OK",
        "candidates" => []
      }

      geocoding_response = %{
        "status" => "OK",
        "results" => [%{
          "formatted_address" => "Mountain View, CA, USA",
          "geometry" => %{
            "location" => %{"lat" => 37.4224764, "lng" => -122.0842499}
          },
          "address_components" => [
            %{
              "long_name" => "Mountain View",
              "short_name" => "MV",
              "types" => ["locality", "political"]
            },
            %{
              "long_name" => "United States",
              "short_name" => "US",
              "types" => ["country", "political"]
            }
          ]
        }]
      }

      expect(HTTPoison.Mock, :get, 2, fn url, [], [follow_redirect: true] ->
        if String.contains?(url, "place/findplacefromtext") do
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(places_response)}}
        else
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(geocoding_response)}}
        end
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Mountain View")
      assert result["city"]["name"] == "Mountain View"
      assert result["country"]["name"] == "United States"
    end
  end

  # Add more test cases for lookup_place_id and lookup_geocode...
end
