# Debug Scripts

This directory contains various debugging scripts for testing and troubleshooting the application.

## Script Categories

### System Tests
- `test_full_job.exs` - Tests running a full scraping job
- `test_insert.exs` - Tests database insertions
- `test_cascade_deletion.exs` - Tests cascading deletions
- `test_performer_deletion.exs` - Tests performer deletion
- `test_problematic_venues.exs` - Tests handling of problematic venues

### Image Processing Tests
- `refresh_images.exs` - Tests image refreshing
- `test_image_refresher.exs` - Tests the image refresher
- `populate_image_galleries.exs` - Tests populating image galleries
- `force_refresh_direct_test.exs` - Tests the force refresh feature directly (demonstrates the fix)
- `direct_test.exs` - Simple test demonstrating the process dictionary isolation issue

### Time and Venue Tests
- `test_time_conversion.exs` - Tests time conversion
- `test_time_extraction.exs` - Tests extracting times from text
- `test_venue_extraction.exs` - Tests venue extraction
- `test_postcode_lookup.exs` - Tests postcode lookup

### Scraper Tests
- `test_geeks_who_drink.exs` - Tests the Geeks Who Drink scraper
- `test_inquizition_job.exs` - Tests the Inquizition scraper job
- `test_rate_limiting.exs` - Tests rate limiting

### Helpers
- `debug_helpers.ex` - Contains helper functions for debugging

## Force Refresh Images Issue

The following files specifically test and demonstrate the fix for the force_refresh_images flag not propagating through Tasks:

- `direct_test.exs` - A minimal script that demonstrates the process isolation issue with Task processes
- `force_refresh_direct_test.exs` - A comprehensive test that verifies our fix works correctly

For more information on the force refresh issue and fix, see `docs/ELIXIR_PROCESS_ISOLATION_FORCE_REFRESH_FIX.md` 