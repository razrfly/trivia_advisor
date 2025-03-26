# Force Image Refresh Fix

## Issue Description

The `force_refresh_images` parameter was being passed correctly through the scraping pipelines, but images weren't actually being refreshed when the flag was set to `true`. The issue was that in several places, the code had been modified to use hardcoded `true` values for the `force_refresh` flag, which meant that:

1. When the flag was set to `true`, images were correctly refreshed (because of the hardcoded `true`)
2. But when the flag was set to `false`, images were still being refreshed (also because of the hardcoded `true`)

This made the flag appear non-functional, as images were always being refreshed regardless of the flag value.

## Fixed Locations

We had to remove hardcoded `true` values from several places and properly respect the `force_refresh_images` flag passed through the system:

1. **In EventStore.download_hero_image function**:
   - Changed to use the proper value from process dictionary instead of hardcoded `true`.

2. **In QuizmeistersDetailJob.process_hero_image function**:
   - Improved logging for clarity.
   - Ensured it uses the value from process dictionary.

3. **In QuizmeistersDetailJob.safe_download_performer_image function**:
   - Added an optional parameter to override the value for testing.
   - Improved logging with `inspect()` for better debugging.
   - Ensured proper capturing of the value for Task usage.

## Verification

We created specialized testing scripts to verify the functionality:

1. **direct_image_refresh_test.exs** - Tests the ImageDownloader functions directly:
   - Confirmed the implementation correctly reuses existing images when `force_refresh=false`.
   - Confirmed it properly deletes and re-downloads images when `force_refresh=true`.

2. **test_fixed_force_refresh.exs** - Tests the full Oban job pipeline:
   - Adds instrumentation to track the flag as it passes through the system.
   - Verifies that with the fixes applied, the flag propagates correctly through the entire pipeline.

## Running the Tests

To verify the fix:

```bash
# Test the ImageDownloader implementation directly
mix run lib/debug/direct_image_refresh_test.exs

# Test the full pipeline with a real Oban job
mix run lib/debug/test_fixed_force_refresh.exs
```

## Conclusion

The issue was not with the ImageDownloader implementation itself, which correctly handled the `force_refresh` flag. Instead, the problem was that hardcoded `true` values in several places were preventing the flag from having the intended effect throughout the system.

By removing these hardcoded values and ensuring proper propagation of the flag, we've ensured that images are only refreshed when explicitly requested with `force_refresh_images=true`.