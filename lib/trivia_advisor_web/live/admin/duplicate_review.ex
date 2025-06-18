defmodule TriviaAdvisorWeb.Live.Admin.DuplicateReview do
  use TriviaAdvisorWeb, :live_view

  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Services.VenueMergeService

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    filter_type = params["filter_type"] || "all"
    sort_by = params["sort_by"] || "name"
    page = String.to_integer(params["page"] || "1")

    socket
    |> assign(:page_title, "Duplicate Venues")
    |> assign(:duplicate_pairs, load_duplicate_pairs(filter_type, sort_by, page))
    |> assign(:filter_type, filter_type)
    |> assign(:sort_by, sort_by)
    |> assign(:current_page, page)
    |> assign(:total_pairs, count_duplicate_pairs(filter_type))
    |> assign(:per_page, 10)
  end

  defp apply_action(socket, :show, %{"venue1_id" => venue1_id, "venue2_id" => venue2_id}) do
    venue1 = Locations.get_venue!(venue1_id) |> TriviaAdvisor.Repo.preload(:city)
    venue2 = Locations.get_venue!(venue2_id) |> TriviaAdvisor.Repo.preload(:city)

    socket
    |> assign(:page_title, "Compare Venues")
    |> assign(:venue1, venue1)
    |> assign(:venue2, venue2)
    |> assign(:similarity_details, calculate_similarity_details(venue1, venue2))
  end

  @impl true
  def handle_event("filter", %{"filter_type" => filter_type}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{%{filter_type: filter_type, sort_by: socket.assigns.sort_by, page: 1}}")}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{%{filter_type: socket.assigns.filter_type, sort_by: sort_by, page: 1}}")}
  end

  def handle_event("merge_venues", %{"primary_id" => primary_id, "secondary_id" => secondary_id}, socket) do
    primary_id = String.to_integer(primary_id)
    secondary_id = String.to_integer(secondary_id)

    case VenueMergeService.merge_venues(primary_id, secondary_id, %{performed_by: "admin_user"}) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Venues merged successfully!")
         |> push_navigate(to: ~p"/admin/venues/duplicates")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to merge venues: #{inspect(reason)}")}
    end
  end

  def handle_event("reject_duplicate", %{"venue1_id" => venue1_id, "venue2_id" => venue2_id}, socket) do
    # Create a log entry to track that these venues are not duplicates
    venue1_id = String.to_integer(venue1_id)
    venue2_id = String.to_integer(venue2_id)

    case VenueMergeService.create_not_duplicate_log(venue1_id, venue2_id, %{performed_by: "admin_user"}) do
      {:ok, _log} ->
        {:noreply,
         socket
         |> put_flash(:info, "Marked as not duplicate - this pair will no longer appear in the duplicates list")
         |> push_navigate(to: ~p"/admin/venues/duplicates")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to mark as not duplicate: #{inspect(reason)}")}
    end
  end

  # Load duplicate pairs from the database view with filtering, sorting, and pagination
  defp load_duplicate_pairs(filter_type, sort_by, page) do
    offset = (page - 1) * 10

    # Build WHERE clause based on filter
    where_clause = case filter_type do
      "name_postcode_duplicate" -> "WHERE duplicate_type = 'name_postcode_duplicate'"
      "name_city_duplicate" -> "WHERE duplicate_type = 'name_city_duplicate'"
      _ -> ""
    end

    # Build ORDER BY clause
    order_clause = case sort_by do
      "name" -> "ORDER BY venue1_name"
      "created" -> "ORDER BY venue1_created DESC"
      "type" -> "ORDER BY duplicate_type, venue1_name"
      _ -> "ORDER BY venue1_name"
    end

    # Add exclusion for pairs marked as "not duplicate"
    not_duplicate_clause = """
    AND NOT EXISTS (
      SELECT 1 FROM venue_merge_logs vml
      WHERE vml.action_type = 'not_duplicate'
      AND ((vml.primary_venue_id = venue1_id AND vml.secondary_venue_id = venue2_id)
           OR (vml.primary_venue_id = venue2_id AND vml.secondary_venue_id = venue1_id))
    )
    """

    # Combine all WHERE conditions
    combined_where = case where_clause do
      "" -> "WHERE 1=1 #{not_duplicate_clause}"
      existing -> "#{existing} #{not_duplicate_clause}"
    end

    query = """
    SELECT
      venue1_id, venue1_name, venue1_postcode, venue1_city_id, venue1_created,
      venue2_id, venue2_name, venue2_postcode, venue2_city_id, venue2_created,
      duplicate_type
    FROM potential_duplicate_venues
    #{combined_where}
    #{order_clause}
    LIMIT 10 OFFSET #{offset}
    """

    case TriviaAdvisor.Repo.query(query) do
      {:ok, %{rows: rows, columns: columns}} ->
        Enum.map(rows, fn row ->
          columns
          |> Enum.zip(row)
          |> Enum.into(%{})
          |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
        end)
      {:error, _} ->
        []
    end
  end

  # Count duplicate pairs for pagination
  defp count_duplicate_pairs(filter_type) do
    where_clause = case filter_type do
      "name_postcode_duplicate" -> "WHERE duplicate_type = 'name_postcode_duplicate'"
      "name_city_duplicate" -> "WHERE duplicate_type = 'name_city_duplicate'"
      _ -> ""
    end

    # Add exclusion for pairs marked as "not duplicate"
    not_duplicate_clause = """
    AND NOT EXISTS (
      SELECT 1 FROM venue_merge_logs vml
      WHERE vml.action_type = 'not_duplicate'
      AND ((vml.primary_venue_id = venue1_id AND vml.secondary_venue_id = venue2_id)
           OR (vml.primary_venue_id = venue2_id AND vml.secondary_venue_id = venue1_id))
    )
    """

    # Combine all WHERE conditions
    combined_where = case where_clause do
      "" -> "WHERE 1=1 #{not_duplicate_clause}"
      existing -> "#{existing} #{not_duplicate_clause}"
    end

    query = """
    SELECT COUNT(*) FROM potential_duplicate_venues
    #{combined_where}
    """

    case TriviaAdvisor.Repo.query(query) do
      {:ok, %{rows: [[count]]}} -> count
      {:error, _} -> 0
    end
  end



  defp calculate_similarity_details(venue1, venue2) do
    %{
      name_match: venue1.name == venue2.name,
      postcode_match: venue1.postcode == venue2.postcode,
      city_match: venue1.city_id == venue2.city_id,
      similarity_score: calculate_similarity_score(venue1, venue2)
    }
  end

  defp calculate_similarity_score(venue1, venue2) do
    # Simple similarity calculation
    name_score = if venue1.name == venue2.name, do: 40, else: 0
    postcode_score = if venue1.postcode == venue2.postcode, do: 30, else: 0
    city_score = if venue1.city_id == venue2.city_id, do: 30, else: 0

    name_score + postcode_score + city_score
  end
end
