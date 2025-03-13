# Debug Utilities and Test Scripts

This folder contains utility scripts and test files used for debugging and testing the Trivia Advisor application. 
These scripts are not part of the production application but are useful for development, troubleshooting, and 
verifying functionality.

## Debug Helper Module

The `debug_helpers.ex` file contains a helper module with utility functions for testing and debugging, 
particularly for the venue processing logic in the Inquizition job.

## Test Scripts

This folder contains various test scripts for different aspects of the application:

- **test_cascade_deletion.exs**: Tests cascade deletion behavior.
- **test_full_job.exs**: Runs a complete Inquizition index job and verifies the results.
- **test_inquizition_job.exs**: Tests the basic functionality of the Inquizition index job.
- **test_insert.exs**: Tests insert operations.
- **test_performer_deletion.exs**: Tests performer deletion functionality.
- **test_postcode_lookup.exs**: Tests postcode lookup for venues.
- **test_problematic_venues.exs**: Tests venue processing for specific venues that had issues.
- **test_time_conversion.exs**: Tests time conversion functionality.
- **test_time_extraction.exs**: Tests extraction of time data from event descriptions.
- **test_venue_extraction.exs**: Tests venue data extraction.

## Usage

To run any of these test scripts, use the `mix run` command, for example:

```bash
mix run lib/debug/test_full_job.exs
```

## Note

These scripts are primarily for development and debugging purposes. They are not covered by automatic tests and may 
require updates to work with changes to the application structure. Use them as a reference and for troubleshooting 
rather than as part of the standard workflow. 