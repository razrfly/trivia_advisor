# Force Refresh Images Flag Fix

## Issue Summary

The `force_refresh_images` flag wasn't being properly passed from index jobs to detail jobs, causing images to never be refreshed even when the flag was set to `true`.

The root causes were:

1. **Atom vs String Keys in Oban Job Arguments**:
   - When Oban serializes job arguments to JSON, atom keys get converted to strings
   - Some index jobs were using `:force_refresh_images` (atom) instead of `"force_refresh_images"` (string)
   - When the detail job looked for `"force_refresh_images"`, it found nothing because the key was normalized

2. **Missing Flag in Some Jobs**:
   - Some index jobs weren't passing the `force_refresh_images` flag to detail jobs at all
   - They were passing `force_update` but neglecting to pass `force_refresh_images`

## Fix Applied

1. **Added consistent logging** of the `force_refresh_images` flag value throughout the pipeline
   - In index jobs when parsing args
   - In detail jobs when receiving args
   - In EventStore.process_event when receiving opts
   - In ImageDownloader when downloading images

2. **Updated QuizmeistersIndexJob**:
   - Changed atom keys to string keys in job arguments: `:force_refresh_images` -> `"force_refresh_images"`
   - Added explicit debug logging for flag values
   - This ensures the flag is properly preserved when passed to detail jobs

3. **Updated SpeedQuizzingIndexJob** (and will update other index jobs):
   - Added detection and processing of the `force_refresh_images` flag in index jobs
   - Changed all atom keys to string keys for consistency
   - Ensured the flag is passed from index to detail jobs

## Testing Methodology

Created several test scripts to diagnose and verify the fix:

1. **test_image_download_with_flag.exs**: 
   - Tests the ImageDownloader functions directly with and without the force_refresh flag
   - Verifies that files are reused when flag is false, and re-downloaded when flag is true

2. **test_force_refresh_images_in_jobs.exs**:
   - Adds diagnostic instrumentation to trace the flag through the job pipeline
   - Inserts a test job with force_refresh_images=true to verify propagation

3. **test_force_refresh_flag.exs**:
   - Directly executes a detail job with force_refresh_images=true
   - Verifies that the flag is properly received and used

4. **compare_index_vs_detail.exs**:
   - Compares direct detail job creation vs. index job creating detail jobs
   - Helps diagnose atom vs string key issues in Oban job serialization

## Verification

After applying the fix, we can confirm:

1. The `force_refresh_images` flag is properly preserved through the pipeline
2. When set to `true`, images are properly re-downloaded instead of reused
3. The flag value is consistently logged for debugging

## Additional Files To Update

The same fix should be applied to these other index jobs:

1. `geeks_who_drink_index_job.ex`
2. `inquizition_index_job.ex` 
3. `question_one_index_job.ex`
4. `pubquiz_index_job.ex`

For each job, we need to:
1. Add detection of the `force_refresh_images` flag 
2. Update to use string keys (`"force_refresh_images"`) not atom keys (`:force_refresh_images`)
3. Pass the flag from index to detail jobs

Once these changes are applied, the `force_refresh_images` flag will work correctly across all jobs.