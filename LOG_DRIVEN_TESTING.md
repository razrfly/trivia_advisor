# Log-Driven Testing for Oban Jobs

## Current State and Problems

Our current approach to testing Oban scraper jobs has several issues:

1. **Brittle Tests**: We try to mock or simulate internal behavior, file system operations, and external API responses, making tests fragile and high-maintenance.

2. **Hard-coded Scraper Logic**: Tests are tightly coupled to specific scrapers (e.g., QuizMeisters), making them hard to reuse across different data sources.

3. **Complex Mocking**: We use extensive mocking with libraries like `Mock`, creating overhead and complexity.

4. **Implementation Details**: Tests focus on implementation details rather than actual job behavior.

5. **Filesystem Testing**: We're trying to test file operations directly, which is error-prone and environment-dependent.

## New Approach: Log-Driven Testing

Instead of mocking/simulating behavior, we'll focus on the real source of truth: **job logs**. The new approach will:

1. Enhance logging in jobs to capture meaningful state changes and decisions
2. Run jobs with `perform_job/2` in test mode
3. Capture logs using `ExUnit.CaptureLog`
4. Assert on log messages as the primary validation mechanism

This approach is more resilient because it validates *what the job actually did* rather than trying to simulate *how it did it*.

## Benefits

1. **Reduced Complexity**: Fewer mocks, simpler test setup
2. **Resilience to Change**: Tests remain valid when implementation details change
3. **Focus on Behavior**: Tests validate what actually matters - the job's behavior
4. **Portable**: Works across different scrapers with minimal changes
5. **Simpler Debugging**: Clear logs make it easier to diagnose failures

## Implementation Plan

1. **Remove current failing tests** related to image downloading/deleting
2. **Enhance job logging** to capture key events with meaningful, consistent patterns
3. **Create generic test modules** that can be reused across scrapers
4. **Convert existing tests** to the log-driven approach
5. **Standardize log messages** across different jobs (index, detail, etc.)

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
# Generic test for any detail job
test "processes venue images correctly with force_refresh_images=true", %{venue_data: venue_data} do
  # Enable force refresh
  Process.put(:force_refresh_images, true)
  
  # Run job and capture logs
  log = capture_log(fn ->
    perform_job(job_module(), %{"venue_data" => venue_data})
  end)
  
  # Assert log patterns
  assert log =~ "Force image refresh enabled"
  assert log =~ "Deleted image at path:"
  assert log =~ "Downloaded and saved image"
end
```

## Modularizing for Multiple Scrapers

To support different scrapers:

1. Create base test modules with common assertions
2. Use configuration or callbacks to specify scraper-specific details
3. Avoid hard-coding URLs, paths, or scraper-specific logic
4. Use pattern matching on logs rather than exact string matching where appropriate

For example:

```elixir
defmodule TriviaAdvisor.Scraping.BaseDetailJobTest do
  # Common test setups and helpers for all scrapers
  
  # Define callback that specific scraper tests must implement
  @callback job_module() :: module()
  @callback venue_fixture() :: map()
  
  # Shared tests that use callbacks to access scraper-specific implementations
end

defmodule TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJobTest do
  use TriviaAdvisor.Scraping.BaseDetailJobTest
  
  # Implement callbacks for this specific scraper
  def job_module, do: TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob
  def venue_fixture, do: ...
end
```

## Next Steps

1. Remove failing tests focusing on file system operations
2. Update the ImageDownloader module with improved logging
3. Rewrite the test files to use the log-driven approach
4. Extract common patterns to support testing multiple scrapers 