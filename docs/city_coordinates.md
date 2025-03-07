# City Coordinates Automation

## Overview

This document explains how city coordinates are managed in the Trivia Advisor application.

## Background

City coordinates (latitude and longitude) are essential for several key features:

- Finding venues near a specific city
- Calculating distances between venues and city centers
- Supporting spatial queries for map-based features
- Enabling radius-based searches

## Previous Implementation

Previously, city coordinates were updated manually by running a mix task:

```bash
mix cities.update_coordinates
```

This task calculated the average coordinates of all venues in a city and updated the city record. However, this manual process created a dependency on remembering to run the task periodically, especially after adding new venues.

## New Automated Solution

We've implemented an automated solution using Oban scheduled jobs:

### Daily Recalibration Worker

A new Oban worker (`TriviaAdvisor.Locations.Oban.DailyRecalibrateWorker`) now runs automatically at 3 AM every day to:

1. Retrieve all cities from the database
2. Calculate the average coordinates of venues in each city
3. Update the city records with the new coordinates
4. Log the results and any issues encountered
5. Update job metadata with execution statistics

### Implementation Details

- The worker reuses the same calculation logic from the mix task
- Optimized database performance using batch updates via `Repo.update_all/2`
- Efficient handling of cities with no venues (tracks separately instead of treating as errors)
- Reduced log verbosity in production environments
- Detailed statistics in logs including successful updates, cities with no venues, and failures
- Performance timer measures execution duration
- Job metadata is stored in two ways:
  - Pre-initialized in the job when created (empty structure)
  - Directly updated in the database after job completion

### Monitoring and Metrics

Each job execution produces detailed metrics that can be viewed in:

1. **Application logs** with a clear, structured format:
   ```
   Daily city coordinate update completed.
   Duration: 1532ms
   Total cities processed: 120
   Cities updated: 95
   Cities skipped: 25
   Cities failed: 0
   ```

2. **ObanWeb UI** with detailed job metadata visible in the "Meta" field:
   ```json
   {
     "total_cities": 120,
     "updated": 95,
     "skipped": 25,
     "failed": 0,
     "duration_ms": 1532
   }
   ```

The worker directly updates the job's meta field in the database using `Repo.update_all/2`, ensuring the execution statistics are visible in the ObanWeb UI.

### Manual Triggering

While the job runs automatically, you can also trigger it manually through code:

```elixir
# In IEx or from application code:
TriviaAdvisor.Locations.recalibrate_city_coordinates()
```

## Compatibility

The original mix task (`mix cities.update_coordinates`) is still available as a fallback option but should rarely be needed now that updates are automated.

## Future Improvements

Potential future improvements could include:

- Enhanced error handling and reporting
- City-specific coordinate update triggers when venues are added/modified
- Fallback to geocoding API for cities with no venues
- Scheduled email reports summarizing coordinate update status 