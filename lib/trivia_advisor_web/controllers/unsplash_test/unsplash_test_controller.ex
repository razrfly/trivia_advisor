defmodule TriviaAdvisorWeb.UnsplashTestController do
  use TriviaAdvisorWeb, :controller
  alias TriviaAdvisor.Repo

  def index(conn, _params) do
    # Get top 9 cities by venue count using raw SQL to avoid dependency issues
    query = """
    SELECT c.id, c.name, c.country_id, co.name AS country_name, COUNT(v.id) AS venue_count
    FROM cities c
    JOIN countries co ON c.country_id = co.id
    JOIN venues v ON v.city_id = c.id
    GROUP BY c.id, c.name, c.country_id, co.name
    ORDER BY COUNT(v.id) DESC
    LIMIT 9
    """

    %{rows: rows} = Repo.query!(query, [])

    # Format the data
    top_cities = Enum.map(rows, fn [id, name, country_id, country_name, venue_count] ->
      %{
        id: id,
        name: name,
        country_id: country_id,
        country_name: country_name,
        venue_count: venue_count
      }
    end)

    # Get the Unsplash API key
    unsplash_api_key = System.get_env("UNSPLASH_ACCESS_KEY")

    render(conn, :index, top_cities: top_cities, unsplash_api_key: unsplash_api_key)
  end
end
