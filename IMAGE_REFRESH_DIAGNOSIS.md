# Image Refresh Diagnosis and Fix Plan

## Issue Identified

We've identified a critical issue with the `force_refresh_images` flag in the image scraping pipeline. When this flag is set to `true` in job arguments, it's not being correctly propagated to the actual image downloading code, resulting in images not being refreshed when requested.

## Reproduction Steps

We've created a series of diagnostic scripts that confirm the issue:

1. **`minimal_force_refresh_test.exs`** - This script demonstrates that:
   - When calling `ImageDownloader` functions directly with `force_refresh=true`, images are correctly refreshed (deleted and re-downloaded)
   - When running an Oban job with `"force_refresh_images" => true`, the logs show `force_refresh: false` in the actual download calls

To reproduce the issue, run:
```bash
mix run lib/debug/minimal_force_refresh_test.exs
```

The output clearly shows:
- Direct API calls work correctly - images are refreshed when `force_refresh=true`
- When running through the Oban job, we see `force_refresh: false` in logs despite passing `true` in arguments

Sample log output from the Oban job (note the `force_refresh: false`):
```
[info] 📸 Processing event hero image URL: https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg, force_refresh: false
[info] 📥 Downloading image from URL: https://cdn.prod.website-files.com/61ea3abbe6d146ba89ea13d7/655aadddaced22f21dc76fca_qld%20-%2010%20toes.jpg, force_refresh: false
```

## Root Cause

After code review, we've discovered several places where the `force_refresh` flag is being overridden with hardcoded values:

1. In `EventStore.download_hero_image` function:
   ```elixir
   # This is causing the issue - overriding the value from process dictionary
   force_refresh_images = true
   ```

2. In `QuizmeistersDetailJob` at various places where performer images and hero images are processed.

These hardcoded values prevent the flag from having any effect, as it's being overridden regardless of what was passed in the job arguments.

## Fix Plan

1. **Remove hardcoded values** in the following files:
   - `lib/trivia_advisor/events/event_store.ex` - Fix `download_hero_image` to use the process dictionary value
   - `lib/trivia_advisor/scraping/oban/quizmeisters_detail_job.ex` - Fix various performer image and hero image processing functions

2. **Ensure proper flag propagation**:
   - Ensure the flag is correctly passed from index jobs to detail jobs 
   - Ensure Tasks (which run in separate processes) correctly capture the flag value
   - Ensure proper logging to track flag values through the system

3. **Testing Plan**:
   - Create a verification script that runs the fixed code with instrumentation
   - Verify that `force_refresh_images=true` in arguments results in `force_refresh=true` at the actual download level

4. **Documentation**:
   - Document the fix in `FORCE_REFRESH_FIX.md`
   - Include before/after code examples

## Next Steps

1. Fix the hardcoded values in `EventStore.download_hero_image`
2. Fix the hardcoded values in `QuizmeistersDetailJob`
3. Run verification tests to confirm the fix works
4. Document the fix and changes made 