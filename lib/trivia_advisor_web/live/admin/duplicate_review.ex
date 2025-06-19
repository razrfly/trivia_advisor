defmodule TriviaAdvisorWeb.Live.Admin.DuplicateReview do
  use TriviaAdvisorWeb, :live_view

  alias TriviaAdvisor.Locations
  alias TriviaAdvisor.Locations.Venue
  alias TriviaAdvisor.Locations.VenueFuzzyDuplicate
  alias TriviaAdvisor.Services.VenueMergeService
  import Ecto.Query, warn: false
  import TriviaAdvisorWeb.Helpers.FormatHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    view_type = params["view_type"] || "fuzzy"
    filter_type = params["filter_type"] || "all"
    sort_by = params["sort_by"] || if view_type == "fuzzy", do: "confidence", else: "name"
    page = String.to_integer(params["page"] || "1")

    {duplicate_pairs, total_pairs, page_title} = case view_type do
      "simple" ->
        {load_simple_duplicate_pairs(page), count_simple_duplicate_pairs(), "Simple Duplicate Venues"}
      _ ->
        {load_fuzzy_duplicate_pairs(filter_type, sort_by, page), count_fuzzy_duplicate_pairs(filter_type), "Fuzzy Duplicate Venues"}
    end

    socket
    |> assign(:page_title, page_title)
    |> assign(:duplicate_pairs, duplicate_pairs)
    |> assign(:view_type, view_type)
    |> assign(:filter_type, filter_type)
    |> assign(:sort_by, sort_by)
    |> assign(:current_page, page)
    |> assign(:total_pairs, total_pairs)
    |> assign(:per_page, 10)
  end

      defp apply_action(socket, :show, %{"venue1_id" => venue1_id, "venue2_id" => venue2_id}) do
    # Use Repo.get instead of get! to handle cases where venues were already merged/deleted
    venue1 = TriviaAdvisor.Repo.get(Venue, venue1_id)
    venue2 = TriviaAdvisor.Repo.get(Venue, venue2_id)

    # If either venue is missing, clean up the orphaned duplicate records and redirect
    if is_nil(venue1) or is_nil(venue2) do
      cleanup_orphaned_duplicates(venue1_id, venue2_id)

      socket
      |> put_flash(:info, "This duplicate pair was already resolved - venues may have been merged or deleted.")
      |> push_navigate(to: ~p"/admin/venues/duplicates")
    else
      # Preload city data and event sources for both venues
      venue1 = TriviaAdvisor.Repo.preload(venue1, [:city, events: [event_sources: :source]])
      venue2 = TriviaAdvisor.Repo.preload(venue2, [:city, events: [event_sources: :source]])

      # Calculate smart defaults for field overrides
      smart_defaults = calculate_smart_defaults(venue1, venue2)

      socket
      |> assign(:page_title, "Compare Venues")
      |> assign(:venue1, venue1)
      |> assign(:venue2, venue2)
      |> assign(:similarity_details, calculate_similarity_details(venue1, venue2))
      |> assign(:field_overrides, smart_defaults)
    end
  end

  @impl true
  def handle_event("switch_view", %{"view_type" => view_type}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{%{view_type: view_type, page: 1}}")}
  end

  def handle_event("filter", %{"filter_type" => filter_type}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{%{view_type: socket.assigns.view_type, filter_type: filter_type, sort_by: socket.assigns.sort_by, page: 1}}")}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{%{view_type: socket.assigns.view_type, filter_type: socket.assigns.filter_type, sort_by: sort_by, page: 1}}")}
  end

  @allowed_override_fields [:website, :phone, :facebook, :instagram, :slug]

  def handle_event("toggle_field_override", %{"field" => field}, socket) do
    try do
      field_atom = String.to_existing_atom(field)

      unless field_atom in @allowed_override_fields do
        {:noreply, put_flash(socket, :error, "Invalid field for override")}
      else
        current_overrides = socket.assigns.field_overrides || []

        new_overrides = if field_atom in current_overrides do
          List.delete(current_overrides, field_atom)
        else
          [field_atom | current_overrides]
        end

        {:noreply, assign(socket, :field_overrides, new_overrides)}
      end
    rescue
      ArgumentError ->
        {:noreply, put_flash(socket, :error, "Invalid field for override")}
    end
  end

  def handle_event("merge_venues", %{"primary_id" => primary_id, "secondary_id" => secondary_id}, socket) do
    primary_id = String.to_integer(primary_id)
    secondary_id = String.to_integer(secondary_id)
    field_overrides = socket.assigns.field_overrides || []

    merge_options = %{
      performed_by: "admin_user",
      metadata_strategy: :prefer_primary,
      field_overrides: field_overrides,
      notes: if length(field_overrides) > 0 do
        "Admin merge with field overrides: #{Enum.join(field_overrides, ", ")}"
      else
        "Admin merge"
      end
    }

    case VenueMergeService.merge_venues(primary_id, secondary_id, merge_options) do
      {:ok, _result} ->
        success_message = if length(field_overrides) > 0 do
          "Venues merged successfully with field overrides: #{Enum.join(field_overrides, ", ")}"
        else
          "Venues merged successfully!"
        end

        {:noreply,
         socket
         |> put_flash(:info, success_message)
         |> push_navigate(to: ~p"/admin/venues/duplicates")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to merge venues: #{inspect(reason)}")}
    end
  end

  def handle_event("reject_duplicate", %{"fuzzy_duplicate_id" => fuzzy_duplicate_id}, socket) do
    fuzzy_duplicate_id = String.to_integer(fuzzy_duplicate_id)

    case TriviaAdvisor.Repo.get(VenueFuzzyDuplicate, fuzzy_duplicate_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Fuzzy duplicate not found")}

      fuzzy_duplicate ->
        # Check if already processed to prevent race conditions
        if fuzzy_duplicate.status != "pending" do
          {:noreply,
           socket
           |> put_flash(:error, "This duplicate has already been reviewed by another admin")}
        else
          changeset = VenueFuzzyDuplicate.changeset(fuzzy_duplicate, %{
            status: "rejected",
            reviewed_at: DateTime.utc_now(),
            reviewed_by: "admin_user"
          })

          case TriviaAdvisor.Repo.update(changeset) do
            {:ok, _updated} ->
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
    end
  end

  def handle_event("reject_duplicate", %{"venue1_id" => venue1_id, "venue2_id" => venue2_id}, socket) do
    venue1_id = String.to_integer(venue1_id)
    venue2_id = String.to_integer(venue2_id)

    # Find the fuzzy duplicate record for these venues
    fuzzy_duplicate = TriviaAdvisor.Repo.one(
      from fd in VenueFuzzyDuplicate,
      where: (fd.venue1_id == ^venue1_id and fd.venue2_id == ^venue2_id) or
             (fd.venue1_id == ^venue2_id and fd.venue2_id == ^venue1_id),
      where: fd.status == "pending"
    )

    case fuzzy_duplicate do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Fuzzy duplicate not found")}

      fuzzy_duplicate ->
        # Check if already processed to prevent race conditions
        if fuzzy_duplicate.status != "pending" do
          {:noreply,
           socket
           |> put_flash(:error, "This duplicate has already been reviewed by another admin")}
        else
          changeset = VenueFuzzyDuplicate.changeset(fuzzy_duplicate, %{
            status: "rejected",
            reviewed_at: DateTime.utc_now(),
            reviewed_by: "admin_user"
          })

          case TriviaAdvisor.Repo.update(changeset) do
            {:ok, _updated} ->
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
    end
  end

  # Load fuzzy duplicate pairs with confidence scoring, filtering, sorting, and pagination
  defp load_fuzzy_duplicate_pairs(filter_type, sort_by, page) do
    offset = (page - 1) * 10

    base_query = from fd in VenueFuzzyDuplicate,
      join: v1 in Locations.Venue, on: v1.id == fd.venue1_id,
      join: v2 in Locations.Venue, on: v2.id == fd.venue2_id,
      where: fd.status == "pending",
      where: is_nil(v1.deleted_at),
      where: is_nil(v2.deleted_at),
      select: %{
        id: fd.id,
        venue1_id: fd.venue1_id,
        venue1_name: v1.name,
        venue1_postcode: v1.postcode,
        venue1_city_id: v1.city_id,
        venue2_id: fd.venue2_id,
        venue2_name: v2.name,
        venue2_postcode: v2.postcode,
        venue2_city_id: v2.city_id,
        confidence_score: fd.confidence_score,
        name_similarity: fd.name_similarity,
        location_similarity: fd.location_similarity,
        match_criteria: fd.match_criteria
      }

    # Apply confidence filter
    filtered_query = case filter_type do
      "high_confidence" -> from q in base_query, where: q.confidence_score >= 0.90
      "medium_confidence" -> from q in base_query, where: q.confidence_score >= 0.75 and q.confidence_score < 0.90
      "low_confidence" -> from q in base_query, where: q.confidence_score < 0.75
      _ -> base_query
    end

    # Apply sorting
    sorted_query = case sort_by do
      "confidence" -> from q in filtered_query, order_by: [desc: q.confidence_score]
      "name" -> from q in filtered_query, order_by: [asc: q.venue1_name]
      "name_similarity" -> from q in filtered_query, order_by: [desc: q.name_similarity]
      "location_similarity" -> from q in filtered_query, order_by: [desc: q.location_similarity]
      _ -> from q in filtered_query, order_by: [desc: q.confidence_score]
    end

    # Apply pagination
    sorted_query
    |> limit(10)
    |> offset(^offset)
    |> TriviaAdvisor.Repo.all()
  end

  # Count fuzzy duplicate pairs for pagination
  defp count_fuzzy_duplicate_pairs(filter_type) do
    base_query = from fd in VenueFuzzyDuplicate,
      join: v1 in Locations.Venue, on: v1.id == fd.venue1_id,
      join: v2 in Locations.Venue, on: v2.id == fd.venue2_id,
      where: fd.status == "pending",
      where: is_nil(v1.deleted_at),
      where: is_nil(v2.deleted_at)

    # Apply confidence filter
    filtered_query = case filter_type do
      "high_confidence" -> from q in base_query, where: q.confidence_score >= 0.90
      "medium_confidence" -> from q in base_query, where: q.confidence_score >= 0.75 and q.confidence_score < 0.90
      "low_confidence" -> from q in base_query, where: q.confidence_score < 0.75
      _ -> base_query
    end

    TriviaAdvisor.Repo.aggregate(filtered_query, :count, :id)
  end

  # Load simple duplicate pairs from SQL view (legacy system)
  defp load_simple_duplicate_pairs(page) do
    offset = (page - 1) * 10

    result = TriviaAdvisor.Repo.query!("""
      SELECT
        NULL as id,
        venue1_id,
        venue1_name,
        venue1_postcode,
        venue1_city_id,
        venue2_id,
        venue2_name,
        venue2_postcode,
        venue2_city_id,
        NULL as confidence_score,
        NULL as name_similarity,
        NULL as location_similarity,
        ARRAY[duplicate_type] as match_criteria
      FROM potential_duplicate_venues
      ORDER BY venue1_name
      LIMIT 10 OFFSET $1
    """, [offset])

    Enum.map(result.rows, fn row ->
      [id, venue1_id, venue1_name, venue1_postcode, venue1_city_id,
       venue2_id, venue2_name, venue2_postcode, venue2_city_id,
       confidence_score, name_similarity, location_similarity, match_criteria] = row

      %{
        id: id,
        venue1_id: venue1_id,
        venue1_name: venue1_name,
        venue1_postcode: venue1_postcode,
        venue1_city_id: venue1_city_id,
        venue2_id: venue2_id,
        venue2_name: venue2_name,
        venue2_postcode: venue2_postcode,
        venue2_city_id: venue2_city_id,
        confidence_score: confidence_score,
        name_similarity: name_similarity,
        location_similarity: location_similarity,
        match_criteria: match_criteria
      }
    end)
  end

  # Count simple duplicate pairs for pagination
  defp count_simple_duplicate_pairs do
    result = TriviaAdvisor.Repo.query!("SELECT COUNT(*) FROM potential_duplicate_venues")
    result.rows |> List.first() |> List.first()
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

  # Clean up fuzzy duplicate records that reference non-existent venues
  defp cleanup_orphaned_duplicates(venue1_id, venue2_id) do
    from(fd in VenueFuzzyDuplicate,
      where: (fd.venue1_id == ^venue1_id and fd.venue2_id == ^venue2_id) or
             (fd.venue1_id == ^venue2_id and fd.venue2_id == ^venue1_id)
    )
    |> TriviaAdvisor.Repo.delete_all()
  end

  # Calculate smart defaults for field overrides based on business rules
  defp calculate_smart_defaults(venue1, venue2) do
    defaults = []

    # Always keep venue A's slug by default (venue A is older and has better slug)
    defaults = if venue1.slug != venue2.slug do
      [:slug | defaults]
    else
      defaults
    end

    # Always take venue B's website by default (venue B was scraped more recently)
    defaults = if venue1.website != venue2.website and venue2.website do
      [:website | defaults]
    else
      defaults
    end

    defaults
  end

  # Build confirmation text for merge dialogs
  defp build_merge_confirmation_text(primary, secondary, field_overrides) do
    base_text = "Merge #{secondary.name} into #{primary.name}?"

    override_text = if length(field_overrides || []) > 0 do
      "\n\n• Field overrides: #{Enum.join(field_overrides, ", ")}"
    else
      ""
    end

    "#{base_text}#{override_text}\n\n• Events will move to primary venue\n• Images will be combined (no duplicates)\n• Secondary venue will be soft-deleted\n• This cannot be undone"
  end
end
