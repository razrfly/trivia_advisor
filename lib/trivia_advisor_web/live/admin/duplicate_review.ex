defmodule TriviaAdvisorWeb.Live.Admin.DuplicateReview do
  use TriviaAdvisorWeb, :live_view

  require Logger

  alias TriviaAdvisor.Locations.{Venue, VenueFuzzyDuplicate}
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
    |> assign(:per_page, 50)
    |> assign(:selected_pairs, MapSet.new())
    |> assign(:select_all, false)
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

  def handle_event("process_fuzzy_duplicates", _params, socket) do
    Logger.info("🚀 BUTTON CLICKED: Admin triggered fuzzy duplicate processing via Oban job!")

    try do
      Logger.info("🔍 Checking if FuzzyDuplicateProcessingJob module is available...")

      # Check if Oban job module is available
      unless Code.ensure_loaded?(TriviaAdvisor.Scraping.Oban.FuzzyDuplicateProcessingJob) do
        Logger.error("❌ FuzzyDuplicateProcessingJob module not available!")
        {:noreply, put_flash(socket, :error, "Fuzzy duplicate processing job not available")}
      else
        Logger.info("✅ FuzzyDuplicateProcessingJob module loaded successfully")
        Logger.info("🤖 Enqueueing fuzzy duplicate processing Oban job")

        # Enqueue the Oban job
        job_result = TriviaAdvisor.Scraping.Oban.FuzzyDuplicateProcessingJob.new(%{})
                    |> Oban.insert()

        case job_result do
          {:ok, job} ->
            Logger.info("🎯 Oban job enqueued successfully with ID: #{job.id}")
            Logger.info("📋 Job details: queue=#{job.queue}, worker=#{job.worker}")
            {:noreply,
             socket
             |> put_flash(:info, "🤖 Fuzzy duplicate processing job started! Check logs for progress. Job ID: #{job.id}")
             |> push_navigate(to: ~p"/admin/venues/duplicates?#{%{view_type: "fuzzy", page: 1}}")}

          {:error, reason} ->
            Logger.error("❌ Failed to enqueue Oban job: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Failed to start job: #{inspect(reason)}")}
        end
      end
    rescue
      error ->
        Logger.error("💥 ERROR in process_fuzzy_duplicates: #{inspect(error)}")
        Logger.error("🔍 Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:noreply, put_flash(socket, :error, "Failed to start fuzzy duplicate processing: #{inspect(error)}")}
    end
  end

  def handle_event("filter", %{"filter_type" => filter_type}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{safe_redirect_params(socket, %{filter_type: filter_type, page: 1})}")}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    {:noreply,
     socket
     |> push_navigate(to: ~p"/admin/venues/duplicates?#{safe_redirect_params(socket, %{sort_by: sort_by, page: 1})}")}
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

    # Get field overrides from socket assigns if they exist
    field_overrides = Map.get(socket.assigns, :field_overrides, [])

    # Prepare merge options
    merge_options = %{
      performed_by: "admin_user",
      notes: "Merged via admin duplicate review interface",
      metadata_strategy: :combine,
      field_overrides: field_overrides,
      event_strategy: :migrate_all
    }

    # Perform the actual venue merge using VenueMergeService
    case TriviaAdvisor.Locations.merge_venues(primary_id, secondary_id, merge_options) do
      {:ok, result} ->
        # Update the fuzzy duplicate status to reflect the successful merge
        _update_fuzzy_duplicate_status(primary_id, secondary_id, "merged")

        message = "Successfully merged venues! #{result.events_migrated} events migrated. Secondary venue has been soft-deleted."
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> push_navigate(to: ~p"/admin/venues/duplicates?#{safe_redirect_params(socket)}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Venue merge failed: #{inspect(reason)}")}
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

  # Batch processing event handlers
  def handle_event("toggle_select_all", _params, socket) do
    # Toggle based on current state
    new_select_all = !socket.assigns.select_all

    selected_pairs = if new_select_all do
      socket.assigns.duplicate_pairs
      |> Enum.map(fn pair -> "#{pair.venue1_id}-#{pair.venue2_id}" end)
      |> MapSet.new()
    else
      MapSet.new()
    end

    {:noreply,
     socket
     |> assign(:selected_pairs, selected_pairs)
     |> assign(:select_all, new_select_all)}
  end

  def handle_event("toggle_pair_selection", %{"pair_id" => pair_id}, socket) do
    current_selected = socket.assigns.selected_pairs

    # Toggle based on current state
    currently_selected = MapSet.member?(current_selected, pair_id)
    new_selected = if currently_selected do
      MapSet.delete(current_selected, pair_id)
    else
      MapSet.put(current_selected, pair_id)
    end

    # Update select_all based on whether all visible pairs are selected
    all_pairs_on_page = socket.assigns.duplicate_pairs
                       |> Enum.map(fn pair -> "#{pair.venue1_id}-#{pair.venue2_id}" end)
                       |> MapSet.new()

    select_all = MapSet.subset?(all_pairs_on_page, new_selected)

    {:noreply,
     socket
     |> assign(:selected_pairs, new_selected)
     |> assign(:select_all, select_all)}
  end

  def handle_event("batch_merge", _params, socket) do
    selected_pairs = socket.assigns.selected_pairs

    if MapSet.size(selected_pairs) == 0 do
      {:noreply, put_flash(socket, :error, "No pairs selected for batch merge")}
    else
      # Validate all pair IDs before processing
      case Enum.find(selected_pairs, &(!valid_pair_id?(&1))) do
        nil ->
          # Process batch merge in a transaction for consistency
          result = TriviaAdvisor.Repo.transaction(fn ->
            selected_pairs
            |> Enum.map(&process_batch_merge/1)
            |> Enum.reduce(%{success: 0, errors: []}, fn result, acc ->
              case result do
                {:ok, _} -> %{acc | success: acc.success + 1}
                {:error, error} ->
                  # Rollback transaction if any errors occur
                  TriviaAdvisor.Repo.rollback(error)
                  acc
              end
            end)
          end)

          case result do
            {:ok, results} ->
              message = "Successfully merged #{results.success} venue pairs!"
              {:noreply,
               socket
               |> put_flash(:info, message)
               |> assign(:selected_pairs, MapSet.new())
               |> assign(:select_all, false)
               |> push_navigate(to: ~p"/admin/venues/duplicates?#{safe_redirect_params(socket)}")}

            {:error, error} ->
              {:noreply, put_flash(socket, :error, "Batch merge failed: #{error}")}
          end

        invalid_pair_id ->
          {:noreply, put_flash(socket, :error, "Invalid pair ID format: #{invalid_pair_id}")}
      end
    end
  end

  def handle_event("batch_reject", _params, socket) do
    selected_pairs = socket.assigns.selected_pairs

    if MapSet.size(selected_pairs) == 0 do
      {:noreply, put_flash(socket, :error, "No pairs selected for batch reject")}
    else
      # Validate all pair IDs before processing
      case Enum.find(selected_pairs, &(!valid_pair_id?(&1))) do
        nil ->
          # Process batch reject in a transaction for consistency
          result = TriviaAdvisor.Repo.transaction(fn ->
            selected_pairs
            |> Enum.map(&process_batch_reject/1)
            |> Enum.reduce(%{success: 0, errors: []}, fn result, acc ->
              case result do
                {:ok, _} -> %{acc | success: acc.success + 1}
                {:error, error} ->
                  # Rollback transaction if any errors occur
                  TriviaAdvisor.Repo.rollback(error)
                  acc
              end
            end)
          end)

          case result do
            {:ok, results} ->
              message = "Successfully rejected #{results.success} venue pairs!"
              {:noreply,
               socket
               |> put_flash(:info, message)
               |> assign(:selected_pairs, MapSet.new())
               |> assign(:select_all, false)
               |> push_navigate(to: ~p"/admin/venues/duplicates?#{safe_redirect_params(socket)}")}

            {:error, error} ->
              {:noreply, put_flash(socket, :error, "Batch reject failed: #{error}")}
          end

        invalid_pair_id ->
          {:noreply, put_flash(socket, :error, "Invalid pair ID format: #{invalid_pair_id}")}
      end
    end
  end

  # Private helper functions for batch processing
  defp valid_pair_id?(pair_id) do
    case String.split(pair_id, "-") do
      [id1, id2] ->
        case {Integer.parse(id1), Integer.parse(id2)} do
          {{_int1, ""}, {_int2, ""}} -> true
          _ -> false
        end
      _ -> false
    end
  end

  defp process_batch_merge(pair_id) do
    try do
      [venue1_id, venue2_id] = String.split(pair_id, "-") |> Enum.map(&String.to_integer/1)

      # Determine which venue should be primary using VenueMergeService
      case TriviaAdvisor.Locations.determine_primary_venue(venue1_id, venue2_id) do
        {:ok, {primary_id, secondary_id}} ->
          # Prepare merge options for batch operation
          merge_options = %{
            performed_by: "admin_user",
            notes: "Merged via batch operation in admin duplicate review",
            metadata_strategy: :combine,
            event_strategy: :migrate_all
          }

          # Perform the actual venue merge
          case TriviaAdvisor.Locations.merge_venues(primary_id, secondary_id, merge_options) do
            {:ok, result} ->
              # Update the fuzzy duplicate status to reflect the successful merge
              _update_fuzzy_duplicate_status(primary_id, secondary_id, "merged")
              {:ok, "Successfully merged venues #{primary_id} ← #{secondary_id} (#{result.events_migrated} events migrated)"}

            {:error, reason} ->
              {:error, "Failed to merge venues #{venue1_id}-#{venue2_id}: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Could not determine primary venue for #{venue1_id}-#{venue2_id}: #{inspect(reason)}"}
      end
    rescue
      error -> {:error, "Exception during merge of #{pair_id}: #{Exception.message(error)}"}
    end
  end

  defp process_batch_reject(pair_id) do
    try do
      [venue1_id, venue2_id] = String.split(pair_id, "-") |> Enum.map(&String.to_integer/1)

      # Find the fuzzy duplicate record for these venues
      fuzzy_duplicate = TriviaAdvisor.Repo.one(
        from fd in VenueFuzzyDuplicate,
        where: (fd.venue1_id == ^venue1_id and fd.venue2_id == ^venue2_id) or
               (fd.venue1_id == ^venue2_id and fd.venue2_id == ^venue1_id),
        where: fd.status == "pending"
      )

      case fuzzy_duplicate do
        nil -> {:error, "Duplicate record not found for #{venue1_id}-#{venue2_id}"}
        duplicate ->
          changeset = VenueFuzzyDuplicate.changeset(duplicate, %{
            status: "rejected",
            reviewed_at: DateTime.utc_now(),
            reviewed_by: "admin_user"
          })

          case TriviaAdvisor.Repo.update(changeset) do
            {:ok, _} -> {:ok, "Rejected pair #{venue1_id}-#{venue2_id}"}
            {:error, reason} -> {:error, "Failed to reject #{venue1_id}-#{venue2_id}: #{inspect(reason)}"}
          end
      end
    rescue
      error ->
        {:error, "Invalid pair ID format #{pair_id}: #{inspect(error)}"}
    end
  end

  # Load fuzzy duplicate pairs with confidence scoring, filtering, sorting, and pagination
  defp load_fuzzy_duplicate_pairs(filter_type, sort_by, page) do
    offset = (page - 1) * 50

    base_query = from fd in VenueFuzzyDuplicate,
      join: v1 in TriviaAdvisor.Locations.Venue, on: v1.id == fd.venue1_id,
      join: v2 in TriviaAdvisor.Locations.Venue, on: v2.id == fd.venue2_id,
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
    |> limit(50)
    |> offset(^offset)
    |> TriviaAdvisor.Repo.all()
  end

  # Count fuzzy duplicate pairs for pagination
  defp count_fuzzy_duplicate_pairs(filter_type) do
    base_query = from fd in VenueFuzzyDuplicate,
      join: v1 in TriviaAdvisor.Locations.Venue, on: v1.id == fd.venue1_id,
      join: v2 in TriviaAdvisor.Locations.Venue, on: v2.id == fd.venue2_id,
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
    offset = (page - 1) * 50

    try do
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
        LIMIT 50 OFFSET $1
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
    rescue
      error ->
        Logger.error("Failed to load simple duplicate pairs: #{inspect(error)}")
        []
    end
  end

  # Count simple duplicate pairs for pagination
  defp count_simple_duplicate_pairs do
    try do
      result = TriviaAdvisor.Repo.query!("SELECT COUNT(*) FROM potential_duplicate_venues")
      result.rows |> List.first() |> List.first()
    rescue
      error ->
        Logger.error("Failed to count simple duplicate pairs: #{inspect(error)}")
        0
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

  # Helper function to safely build redirect parameters
  defp safe_redirect_params(socket, overrides \\ %{}) do
    defaults = %{
      view_type: "fuzzy",
      filter_type: "all",
      sort_by: "confidence",
      page: 1
    }

    current_params = %{
      view_type: Map.get(socket.assigns, :view_type, defaults.view_type),
      filter_type: Map.get(socket.assigns, :filter_type, defaults.filter_type),
      sort_by: Map.get(socket.assigns, :sort_by, defaults.sort_by),
      page: Map.get(socket.assigns, :current_page, defaults.page)
    }

    Map.merge(current_params, overrides)
  end

  # Helper function to update fuzzy duplicate status after a successful merge
  defp _update_fuzzy_duplicate_status(primary_id, secondary_id, status) do
    fuzzy_duplicate = TriviaAdvisor.Repo.one(
      from fd in VenueFuzzyDuplicate,
      where: (fd.venue1_id == ^primary_id and fd.venue2_id == ^secondary_id) or
             (fd.venue1_id == ^secondary_id and fd.venue2_id == ^primary_id),
      where: fd.status == "pending"
    )

    if fuzzy_duplicate do
      changeset = VenueFuzzyDuplicate.changeset(fuzzy_duplicate, %{
        status: status,
        reviewed_at: DateTime.utc_now(),
        reviewed_by: "admin_user"
      })
      TriviaAdvisor.Repo.update(changeset)
    end
  end
end
