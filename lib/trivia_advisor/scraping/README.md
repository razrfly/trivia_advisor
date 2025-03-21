# TriviaAdvisor Scraping Rate Limiting

This documentation describes how rate limiting works for processing large numbers of venues and events in the TriviaAdvisor application.

## Rate Limiting Features

The system includes several features to manage the processing of large numbers of venues/events:

1. **Oban Pruner Plugin**: Automatically cleans up jobs older than 7 days to prevent database bloat
2. **Hourly Job Caps**: Limits the number of jobs scheduled per hour to prevent system overload
3. **Job Spacing**: Spaces out jobs within each hour for smoother processing
4. **Configurable Settings**: Centralized configuration in the RateLimiter module

## Key Configuration

All rate limiting settings are defined in the `TriviaAdvisor.Scraping.RateLimiter` module:

```elixir
@defaults %{
  job_delay_interval: 1,            # Seconds between jobs
  max_attempts: 5,                  # Max retry attempts
  priority: 3,                      # Job priority (lower = higher)
  skip_if_updated_within_days: 5,   # Skip recently processed venues/events
  max_jobs_per_hour: 50             # Maximum jobs to schedule per hour
}
```

## Usage

The RateLimiter provides two main scheduling functions:

### 1. Basic Rate Limiting

`schedule_detail_jobs/3` - Schedules jobs with a simple delay between each job.

```elixir
RateLimiter.schedule_detail_jobs(
  items_to_process,
  DetailJobModule,
  fn item -> %{item_id: item.id} end
)
```

### 2. Hourly Capped Rate Limiting

`schedule_hourly_capped_jobs/3` - Schedules jobs with a maximum number per hour.

```elixir
RateLimiter.schedule_hourly_capped_jobs(
  items_to_process,
  DetailJobModule,
  fn item -> %{item_id: item.id} end
)
```

This is useful for large scraper jobs like GeeksWhoDrink and SpeedQuizzing that process 1000+ venues/events.

## Testing

Use the test script to verify rate limiting functionality:

```bash
mix run lib/debug/test_rate_limiting.exs
```

This will create test jobs and verify they're distributed across hours according to the configured limits.

## Implementation Details

When using hourly capped scheduling:

1. The system calculates how many hours are needed based on the total items and max_jobs_per_hour
2. Jobs are distributed across those hours
3. Within each hour, jobs are spaced evenly
4. The schedule_in parameter is set based on the job's position

Jobs will be processed over time instead of all at once, preventing system overload. 

## Best Practices

### Return Value Handling

When handling return values from scraper functions, follow these principles:

1. **NEVER** write repetitive case statements that handle multiple similar structure variations. Instead, normalize return values with helper functions:

```elixir
# BAD - Don't do this
case process_venue(venue_data, source) do
  {:ok, %{venue: venue, event: {:ok, event_struct}}} ->
    # Handle case 1...
  
  {:ok, %{venue: venue, event: event}} when is_map(event) ->
    # Handle case 2 with duplicate code...
  
  {:ok, %{venue: venue, event: {:ok, %{event: event}}}} ->
    # Handle case 3 with more duplicate code...
end

# GOOD - Do this instead
case process_venue(venue_data, source) do
  {:ok, %{venue: venue} = result} ->
    {event_id, event} = normalize_event_result(result[:event])
    # Process with normalized values
end

# Helper to normalize different result structures
defp normalize_event_result(event_data) do
  case event_data do
    {:ok, %{event: event}} when is_map(event) -> {event.id, event}
    {:ok, event} when is_map(event) -> {event.id, event}
    %{event: event} when is_map(event) -> {event.id, event}
    event when is_map(event) -> {event.id, event}
  end
end
```

2. **ALWAYS** normalize complex data structures inside the functions that produce them, not in the functions that consume them

3. **PREFER** consistent return value shapes across similar functions

4. **USE** pattern guards to differentiate cases, not multiple pattern clauses that do the same thing 