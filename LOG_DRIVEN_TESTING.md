# Log-Driven Testing for Oban Jobs

## Current State and Problems

Our current approach to testing Oban scraper jobs has several issues:

1. **Brittle Tests**: We try to mock or simulate internal behavior, file system operations, and external API responses, making tests fragile and high-maintenance.

2. **Hard-coded Scraper Logic**: Tests are tightly coupled to specific scrapers (e.g., QuizMeisters), making them hard to reuse across different data sources.

3. **Complex Mocking**: We use extensive mocking with libraries like `Mock`, creating overhead and complexity.

4. **Implementation Details**: Tests focus on implementation details rather than actual job behavior.

5. **Fixture Reliance**: We rely too heavily on fixtures, which don't represent the real complexity of our Oban pipeline.

## New Approach: Log-Driven Testing with Real Jobs

Instead of mocking/simulating behavior with fixtures, we'll focus on the real source of truth: **running actual Oban jobs and analyzing their logs**. The new approach will:

1. **Use Real Data**: Run actual Oban jobs with small limits (1-3 venues) to verify real behavior
2. **Enhance logging** in jobs to capture meaningful state changes and decisions
3. **Capture logs** using `ExUnit.CaptureLog`
4. **Assert on log messages** as the primary validation mechanism

This approach is more resilient because it validates *what the job actually did* with real data rather than trying to simulate *how it did it* with fixtures.

## Benefits

1. **Real-World Testing**: Tests use the actual job pipeline and real data
2. **Reduced Complexity**: Fewer mocks, simpler test setup
3. **Resilience to Change**: Tests remain valid when implementation details change
4. **Focus on Behavior**: Tests validate what actually matters - the job's behavior
5. **Simpler Debugging**: Clear logs make it easier to diagnose failures

## Implementation Plan

1. **Remove heavy reliance on fixtures** for Oban job testing
2. **Run actual Oban jobs** with limited result sizes
3. **Enhance job logging** to capture key events with meaningful, consistent patterns
4. **Create generic test modules** that can be reused across scrapers
5. **Standardize log messages** across different jobs (index, detail, etc.)

## Testing Actual Oban Jobs

For comprehensive testing, we need to move beyond fixtures and run actual Oban jobs:

```elixir
# Test with actual job insertion and limit the results to 3 venues
test "index job processes venues correctly with force_refresh_images" do
  # Insert an actual job (with limited venues for testing)
  {:ok, job} = Oban.insert(
    TriviaAdvisor.Scraping.Oban.QuizmeistersIndexJob.new(%{
      "force_refresh_images" => true, 
      "force_update" => true, 
      "limit" => 3
    })
  )
  
  # Run the job and capture logs 
  log = capture_log(fn -> 
    Oban.perform_job(job)
  end)
  
  # Assert on log patterns that demonstrate correct behavior
  assert log =~ "Successfully fetched"
  assert log =~ "Enqueued detail jobs"
  assert log =~ "Force image refresh enabled"
end
```

This approach tests the entire job pipeline with real data but limits the volume to keep tests manageable.

## Log Message Standardization

We'll establish consistent log patterns for critical operations:

```
# Force refresh enabled
"🔄 Force image refresh enabled"

# Image operations
"🗑️ Deleted image at path: ..."
"✅ Downloaded and saved image to: ..."
"⚠️ Skipped image refresh because force_refresh_images was false"

# Job progress
"🔄 Processing venue: ..."
"✅ Successfully processed venue: ..."
```

## Example Test Structure

```elixir
# Test detail job with real data
test "detail job processes a real venue correctly", %{venue_data: venue_data} do
  # Create job args with real venue data (not fixture data)
  args = %{
    "venue" => venue_data,
    "source_id" => venue_data["source_id"],
    "force_refresh_images" => true
  }
  
  # Run job and capture logs
  log = capture_log(fn ->
    {:ok, job} = Oban.insert(TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob.new(args))
    Oban.perform_job(job)
  end)
  
  # Assert log patterns
  assert log =~ "Force image refresh enabled"
  assert log =~ "Processing venue: #{venue_data["name"]}"
  assert log =~ "Successfully processed venue"
end
```

## Modularizing for Multiple Scrapers

To support different scrapers while using real data:

1. Create base test modules with common assertions
2. Use configuration or callbacks to specify scraper-specific details
3. Avoid hard-coding URLs, paths, or scraper-specific logic
4. Use pattern matching on logs rather than exact string matching where appropriate

For example:

```elixir
defmodule TriviaAdvisor.Scraping.BaseScraperJobTest do
  # Common test setups and helpers for all scrapers
  
  # Define callback that specific scraper tests must implement
  @callback job_module() :: module()
  @callback source_base_url() :: String.t()
  
  # Helper to run a job with real data
  def run_job_with_limit(job_module, limit \\ 3) do
    {:ok, job} = Oban.insert(
      job_module.new(%{
        "force_refresh_images" => true, 
        "force_update" => true, 
        "limit" => limit
      })
    )
    
    log = capture_log(fn -> Oban.perform_job(job) end)
    {job, log}
  end
end
```

## Key Principles

1. **Use Real Data**: Whenever possible, test with actual data rather than fixtures
2. **Limit Result Size**: Use the "limit" parameter to restrict processing to 1-3 venues
3. **Focus on Logs**: Validate behavior through log messages, not internal state
4. **End-to-End Testing**: Test the complete job pipeline rather than isolated components
5. **Realistic URLs**: Use real URLs and sources that reflect production behavior

## Next Steps

1. Update tests to insert and run actual Oban jobs
2. Limit job result sizes to keep tests manageable (1-3 venues)
3. Improve logging to capture all key decision points
4. Assert on log messages to validate correct behavior
5. Move away from fixture-based testing for Oban jobs 