defmodule TriviaAdvisor.Scraping.GoogleLookupTest do
  use ExUnit.Case, async: true
  alias TriviaAdvisor.Scraping.GoogleLookup

  # We'll use bypass to mock the Google APIs
  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  describe "lookup_address/1" do
    test "returns enriched place data with country and city", %{bypass: bypass, base_url: base_url} do
      # Mock findplacefromtext response
      Bypass.expect_once(bypass, "GET", "/maps/api/place/findplacefromtext/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "status": "OK",
          "candidates": [{
            "place_id": "ChIJK",
            "formatted_address": "4 Pennsylvania Plaza, New York, NY 10001",
            "geometry": {
              "location": {"lat": 40.7505, "lng": -73.9934}
            },
            "name": "Madison Square Garden"
          }]
        }))
      end)

      # Mock place details response
      Bypass.expect_once(bypass, "GET", "/maps/api/place/details/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "status": "OK",
          "result": {
            "place_id": "ChIJK",
            "formatted_address": "4 Pennsylvania Plaza, New York, NY 10001",
            "geometry": {
              "location": {"lat": 40.7505, "lng": -73.9934}
            },
            "name": "Madison Square Garden",
            "address_components": [
              {
                "long_name": "New York",
                "short_name": "NYC",
                "types": ["locality", "political"]
              },
              {
                "long_name": "United States",
                "short_name": "US",
                "types": ["country", "political"]
              }
            ]
          }
        }))
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Madison Square Garden", base_url: base_url)
      assert result["place_id"] == "ChIJK"
      assert result["country"]["name"] == "United States"
      assert result["country"]["code"] == "US"
      assert result["city"]["name"] == "New York"
      assert result["city"]["code"] == "NYC"
    end

    test "handles geocoding fallback with location components", %{bypass: bypass, base_url: base_url} do
      Bypass.expect_once(bypass, "GET", "/maps/api/place/findplacefromtext/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": "OK", "candidates": []}))
      end)

      Bypass.expect_once(bypass, "GET", "/maps/api/geocode/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "status": "OK",
          "results": [{
            "formatted_address": "1600 Amphitheatre Parkway, Mountain View, CA 94043",
            "geometry": {
              "location": {"lat": 37.4224764, "lng": -122.0842499}
            },
            "address_components": [
              {
                "long_name": "Mountain View",
                "short_name": "MV",
                "types": ["locality", "political"]
              },
              {
                "long_name": "United States",
                "short_name": "US",
                "types": ["country", "political"]
              }
            ]
          }]
        }))
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Google HQ", base_url: base_url)
      assert result["country"]["name"] == "United States"
      assert result["city"]["name"] == "Mountain View"
    end
  end

  describe "location components" do
    test "extracts location components from Places API", %{bypass: bypass, base_url: base_url} do
      # Mock findplacefromtext response
      Bypass.expect_once(bypass, "GET", "/maps/api/place/findplacefromtext/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "status": "OK",
          "candidates": [{
            "place_id": "test_place_id",
            "formatted_address": "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA",
            "name": "Google Building"
          }]
        }))
      end)

      # Mock place details response
      Bypass.expect_once(bypass, "GET", "/maps/api/place/details/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "status": "OK",
          "result": {
            "name": "Google Building",
            "formatted_address": "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA",
            "address_components": [
              {
                "long_name": "Mountain View",
                "short_name": "MV",
                "types": ["locality", "political"]
              },
              {
                "long_name": "California",
                "short_name": "CA",
                "types": ["administrative_area_level_1", "political"]
              },
              {
                "long_name": "United States",
                "short_name": "US",
                "types": ["country", "political"]
              }
            ]
          }
        }))
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Google Building", base_url: base_url)
      assert result["country"]["name"] == "United States"
      assert result["country"]["code"] == "US"
      assert result["city"]["name"] == "Mountain View"
      assert result["city"]["code"] == "MV"
      assert result["state"]["name"] == "California"
      assert result["state"]["code"] == "CA"
    end

    test "extracts location components from Geocoding API", %{bypass: bypass, base_url: base_url} do
      # Mock empty Places API response to force geocoding
      Bypass.expect_once(bypass, "GET", "/maps/api/place/findplacefromtext/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"status": "OK", "candidates": []}))
      end)

      # Mock Geocoding API response
      Bypass.expect_once(bypass, "GET", "/maps/api/geocode/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({
          "status": "OK",
          "results": [{
            "formatted_address": "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA",
            "address_components": [
              {
                "long_name": "Mountain View",
                "short_name": "MV",
                "types": ["locality", "political"]
              },
              {
                "long_name": "California",
                "short_name": "CA",
                "types": ["administrative_area_level_1", "political"]
              },
              {
                "long_name": "United States",
                "short_name": "US",
                "types": ["country", "political"]
              }
            ]
          }]
        }))
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Test Address", base_url: base_url)
      assert result["country"]["name"] == "United States"
      assert result["country"]["code"] == "US"
      assert result["city"]["name"] == "Mountain View"
      assert result["city"]["code"] == "MV"
      assert result["state"]["name"] == "California"
      assert result["state"]["code"] == "CA"
    end
  end

  # Add more test cases for lookup_place_id and lookup_geocode...
end
