defmodule TriviaAdvisorWeb.Components.OpenGraphComponent do
  use Phoenix.Component
  require Logger

  @doc """
  Renders Open Graph meta tags for social media sharing.

  ## Examples
      <.open_graph_tags
        type="event"
        title="Pub Quiz at Venue Name"
        description="Event description here"
        image_url="https://example.com/image.jpg"
        url="https://quizadvisor.com/venues/venue-slug"
      />
  """
  attr :type, :string, default: "website"
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :image_url, :string, required: true
  attr :image_width, :integer, default: 1200
  attr :image_height, :integer, default: 630
  attr :url, :string, required: true
  attr :site_name, :string, default: "QuizAdvisor"

  def open_graph_tags(assigns) do
    # Ensure the image URL is a full URL
    assigns = Map.update(assigns, :image_url, "", fn url ->
      if is_binary(url) && String.starts_with?(url, "http"), do: url, else: url
    end)

    # Ensure the page URL is a full URL
    assigns = Map.update(assigns, :url, "", fn url ->
      if is_binary(url) && String.starts_with?(url, "http"), do: url, else: url
    end)

    ~H"""
    <meta property="og:type" content={@type}>
    <meta property="og:title" content={@title}>
    <meta property="og:description" content={@description}>
    <meta property="og:image" content={@image_url}>
    <meta property="og:image:width" content={@image_width}>
    <meta property="og:image:height" content={@image_height}>
    <meta property="og:url" content={@url}>
    <meta property="og:site_name" content={@site_name}>

    <!-- Twitter Card tags -->
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content={@title}>
    <meta name="twitter:description" content={@description}>
    <meta name="twitter:image" content={@image_url}>
    """
  end
end
