defmodule TriviaAdvisorWeb.Components.Breadcrumbs do
  @moduledoc """
  Provides breadcrumb navigation components and helpers.
  """
  use Phoenix.Component

  @doc """
  Renders a breadcrumb navigation bar.

  ## Examples

      <.breadcrumbs items={[
        %{name: "Home", url: ~p"/"},
        %{name: "United Kingdom", url: ~p"/countries/united-kingdom"},
        %{name: "London", url: ~p"/cities/london"},
        %{name: "The Red Lion", url: nil}
      ]} />
  """
  attr :items, :list, required: true, doc: "List of breadcrumb items with name and url"
  attr :class, :string, default: "", doc: "Additional classes for the container"

  def breadcrumbs(assigns) do
    ~H"""
    <nav class={"flex py-3 text-sm text-gray-600 #{@class}"} aria-label="Breadcrumb">
      <ol class="inline-flex items-center space-x-1 md:space-x-3 flex-wrap">
        <%= for {item, index} <- Enum.with_index(@items) do %>
          <li class="inline-flex items-center">
            <%= if index > 0 do %>
              <svg class="w-3 h-3 mx-1 text-gray-400" aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 6 10">
                <path stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="m1 9 4-4-4-4"/>
              </svg>
            <% end %>

            <%= if item.url do %>
              <.link navigate={item.url} class="inline-flex items-center text-sm font-medium text-gray-700 hover:text-indigo-600">
                <%= item.name %>
              </.link>
            <% else %>
              <span class="ml-1 text-sm font-medium text-gray-500">
                <%= item.name %>
              </span>
            <% end %>
          </li>
        <% end %>
      </ol>
    </nav>
    """
  end
end
