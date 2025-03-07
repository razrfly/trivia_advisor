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

### Implementation Details

- The worker reuses the same calculation logic from the mix task
- It handles cities with no venues gracefully (logs a warning but doesn't fail)
- Detailed logs are generated to track successful and failed updates
- A performance timer measures execution duration

### Manual Triggering

While the job runs automatically, you can also trigger it manually through code:

```elixir
# In IEx or from application code:
TriviaAdvisor.Locations.recalibrate_city_coordinates()
```

## Compatibility

The original mix task (`mix cities.update_coordinates`) is still available as a fallback option but should rarely be needed now that updates are automated.

## Monitoring

You can monitor the job's execution through:

1. Application logs (look for "Starting daily city coordinates update" and "Completed daily city coordinates update")
2. The Oban web dashboard (at `/oban` if configured)

## Future Improvements

Potential future improvements could include:

- Enhanced error handling and reporting
- City-specific coordinate update triggers when venues are added/modified
- Fallback to geocoding API for cities with no venues
- Scheduled email reports summarizing coordinate update status 