defmodule TriviaAdvisor.Scraping.GoogleLookupTest do
  use ExUnit.Case, async: true
  alias TriviaAdvisor.Scraping.GoogleLookup

  # We'll use bypass to mock the Google APIs
  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, base_url: "http://localhost:#{bypass.port}"}
  end

  describe "lookup_address/1" do
    test "returns place data when found via Places API", %{bypass: bypass, base_url: base_url} do
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

      assert {:ok, result} = GoogleLookup.lookup_address("Madison Square Garden", base_url: base_url)
      assert result["place_id"] == "ChIJK"
    end

    test "falls back to Geocoding API when Places API returns no results", %{bypass: bypass, base_url: base_url} do
      # Mock Places API response (no results)
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
            "formatted_address": "Nonexistent Place 1234",
            "geometry": {
              "location": {"lat": 40.7128, "lng": -74.0060}
            }
          }]
        }))
      end)

      assert {:ok, result} = GoogleLookup.lookup_address("Nonexistent Place 1234", base_url: base_url)
      assert result["results"]
    end
  end

  # Add more test cases for lookup_place_id and lookup_geocode...
end
