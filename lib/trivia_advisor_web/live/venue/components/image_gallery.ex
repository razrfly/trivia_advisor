defmodule TriviaAdvisorWeb.VenueLive.Components.ImageGallery do
  use TriviaAdvisorWeb, :html
  alias TriviaAdvisorWeb.Helpers.S3Helpers

  @doc """
  Renders a gallery of venue images.

  Takes a venue, a function to get images, and a function to count images.

  ## Examples
      <.gallery
        venue={venue}
        get_venue_image_at_position={&get_venue_image_at_position/2}
        count_available_images={&count_available_images/1}
      />
  """
  attr :venue, :map, required: true
  attr :get_venue_image_at_position, :any, required: true
  attr :count_available_images, :any, required: true
  attr :navigate_to, :string, default: nil

  def gallery(assigns) do
    # Process attributes before passing to template
    available_images = assigns.count_available_images.(assigns.venue)
    assigns = assign(assigns, :available_images, available_images)

    ~H"""
    <div class="mb-8 overflow-hidden rounded-lg">
      <div class="flex flex-wrap">
        <%= cond do %>
          <% @available_images >= 5 -> %>
            <!-- 5+ images layout (current layout) -->
            <div class="w-1/2 p-1">
              <img
                src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 0))}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2">
              <div class="flex flex-wrap">
                <div class="w-1/2 p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 1))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-tr-lg"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 2))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 3))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 4))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-br-lg"
                  />
                </div>
              </div>
            </div>
          <% @available_images == 4 -> %>
            <!-- 4 images layout -->
            <div class="w-1/2 p-1">
              <img
                src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 0))}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2">
              <div class="flex flex-wrap">
                <div class="w-full p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 1))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-tr-lg"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 2))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 3))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-br-lg"
                  />
                </div>
              </div>
            </div>
          <% @available_images == 3 -> %>
            <!-- 3 images layout -->
            <div class="w-1/2 p-1">
              <img
                src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 0))}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2">
              <div class="flex flex-wrap">
                <div class="w-full p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 1))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-tr-lg"
                  />
                </div>
                <div class="w-full p-1">
                  <img
                    src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 2))}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-br-lg"
                  />
                </div>
              </div>
            </div>
          <% @available_images == 2 -> %>
            <!-- 2 images layout -->
            <div class="w-1/2 p-1">
              <img
                src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 0))}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2 p-1">
              <img
                src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 1))}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tr-lg rounded-br-lg"
              />
            </div>
          <% @available_images == 1 -> %>
            <!-- 1 image layout -->
            <div class="w-full p-1">
              <img
                src={S3Helpers.safe_url(@get_venue_image_at_position.(@venue, 0))}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-lg"
              />
            </div>
          <% true -> %>
            <!-- No images - fallback to simple hero -->
            <div class="w-full p-1">
              <img
                src={S3Helpers.safe_url(@venue.hero_image_url || "https://placehold.co/1200x400?text=#{@venue.name}")}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-lg"
              />
            </div>
        <% end %>
      </div>
    </div>
    """
  end
end
