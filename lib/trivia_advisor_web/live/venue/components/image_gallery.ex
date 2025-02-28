defmodule TriviaAdvisorWeb.VenueLive.Components.ImageGallery do
  use TriviaAdvisorWeb, :html

  def gallery(assigns) do
    ~H"""
    <div class="mb-8 overflow-hidden rounded-lg">
      <div class="flex flex-wrap">
        <% available_images = @count_available_images.(@venue) %>
        <%= cond do %>
          <% available_images >= 5 -> %>
            <!-- 5+ images layout (current layout) -->
            <div class="w-1/2 p-1">
              <img
                src={@get_venue_image_at_position.(@venue, 0)}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2">
              <div class="flex flex-wrap">
                <div class="w-1/2 p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 1)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-tr-lg"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 2)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 3)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 4)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-br-lg"
                  />
                </div>
              </div>
            </div>
          <% available_images == 4 -> %>
            <!-- 4 images layout -->
            <div class="w-1/2 p-1">
              <img
                src={@get_venue_image_at_position.(@venue, 0)}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2">
              <div class="flex flex-wrap">
                <div class="w-full p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 1)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-tr-lg"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 2)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover"
                  />
                </div>
                <div class="w-1/2 p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 3)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-br-lg"
                  />
                </div>
              </div>
            </div>
          <% available_images == 3 -> %>
            <!-- 3 images layout -->
            <div class="w-1/2 p-1">
              <img
                src={@get_venue_image_at_position.(@venue, 0)}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2">
              <div class="flex flex-wrap">
                <div class="w-full p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 1)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-tr-lg"
                  />
                </div>
                <div class="w-full p-1">
                  <img
                    src={@get_venue_image_at_position.(@venue, 2)}
                    alt={@venue.name}
                    class="h-48 w-full object-cover rounded-br-lg"
                  />
                </div>
              </div>
            </div>
          <% available_images == 2 -> %>
            <!-- 2 images layout -->
            <div class="w-1/2 p-1">
              <img
                src={@get_venue_image_at_position.(@venue, 0)}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tl-lg rounded-bl-lg"
              />
            </div>
            <div class="w-1/2 p-1">
              <img
                src={@get_venue_image_at_position.(@venue, 1)}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-tr-lg rounded-br-lg"
              />
            </div>
          <% available_images == 1 -> %>
            <!-- 1 image layout -->
            <div class="w-full p-1">
              <img
                src={@get_venue_image_at_position.(@venue, 0)}
                alt={@venue.name}
                class="h-96 w-full object-cover rounded-lg"
              />
            </div>
          <% true -> %>
            <!-- No images - fallback to simple hero -->
            <div class="w-full p-1">
              <img
                src={@venue.hero_image_url || "https://placehold.co/1200x400?text=#{@venue.name}"}
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
