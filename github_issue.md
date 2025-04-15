# Replace Mock Data with Real Venue Data on Homepage

## Background

Currently, the homepage (`HomeLive.Index`) uses mock data for featured venues, popular cities, and upcoming events. This creates issues with maintenance and doesn't showcase actual data. We need to replace these mock functions with real database queries.

## Objective

Replace mock data on the homepage with real database queries showing the newest venues with events, ensuring diversity across cities and countries.

## Detailed Requirements

### 1. Featured Venues Query

Create a query in `TriviaAdvisor.Locations` to:
- Fetch newest venues that have scheduled events
- Ensure diversity by selecting venues from different cities/countries
- Sort by creation date (newest first)
- Include all necessary fields (id, name, slug, rating, address, etc.)
- Limit to a reasonable number for display (4-8)

Example function signature:
```elixir
def get_featured_venues(limit \\ 4) do
  # Query newest venues with events from diverse locations
  # This should prioritize venues from different cities/countries
end
```

### 2. Venue Card Component Enhancement

Ensure the `VenueCard` component:
- Handles real venue data structures robustly
- Safely accesses fields using `Map.get/3` with defaults
- Properly handles slugs similar to city slugs:
  ```elixir
  venue_slug = Map.get(venue, :slug) ||
               String.downcase(venue.name) |> String.replace(~r/[^a-z0-9]+/, "-")
  ```
- Properly formats different time formats
- Handles venue entry fees correctly
- Displays ratings consistently

### 3. Reuse Existing Helpers

Leverage our existing helper modules:
- `ImageHelpers` for venue images
- `FormatHelpers` for formatting days/times
- `CurrencyHelpers` for entry fee display
- `LocalizationHelpers` for time zone handling

### 4. Homepage Update

Modify `HomeLive.Index`:
- Replace `mock_featured_venues()` with call to the new query function
- Consider caching results to minimize DB hits
- Maintain consistent UI between mock and real data

### 5. Testing Strategy

Update `index_test.exs` to:
- Test with real or fixed test data instead of mocks
- Verify venue cards render correctly
- Ensure all links work correctly
- Validate slugs are properly generated
- Test edge cases (venues without events, ratings, etc.)

## Implementation Notes

- Look at `CityLive.Show` for venue display patterns to maintain consistency
- Ensure proper preloading to avoid N+1 queries
- Consider adding filters/sorting options for future enhancement
- Structure the query to be performant and cacheable

## Acceptance Criteria

- [ ] Homepage displays real venue data from database
- [ ] Venues are displayed from different cities/countries when possible
- [ ] Venue cards match design and include all required information
- [ ] Venue slugs work correctly for navigation
- [ ] No KeyErrors or crashes when handling venues with missing fields
- [ ] Tests pass and properly validate functionality

## Affected Files

- `lib/trivia_advisor/locations.ex` - New query function
- `lib/trivia_advisor_web/live/home/index.ex` - Update to use real data
- `lib/trivia_advisor_web/components/ui/venue_card.ex` - Component enhancements
- `test/trivia_advisor_web/live/home/index_test.exs` - Updated tests 