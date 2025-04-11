defmodule TriviaAdvisorWeb.Live.Venue.Components.Header do
  @moduledoc """
  Header component for the Venue Show page.
  """
  use TriviaAdvisorWeb, :live_component

  def render(assigns) do
    ~H"""
    <div>
      <!-- Breadcrumbs -->
      <TriviaAdvisorWeb.Components.Breadcrumbs.breadcrumbs items={@breadcrumb_items} class="mb-4" />

      <!-- Venue Title -->
      <h1 class="mb-6 text-3xl font-bold text-gray-900"><%= @venue.name %></h1>
    </div>
    """
  end
end
