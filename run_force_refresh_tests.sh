#!/bin/bash

# This script runs all the force refresh flag tests and saves the output

echo "=== Running Force Refresh Flag Tests ==="
echo "Saving results to force_refresh_test_output.log"

# Create a log file for the output
LOG_FILE="force_refresh_test_output.log"
echo "Test run started at $(date)" > $LOG_FILE

# Run the basic image download test
echo "\n\n=== 1. Testing basic image download functionality ===" | tee -a $LOG_FILE
echo "Running: mix run lib/debug/test_image_download_with_flag.exs" | tee -a $LOG_FILE
mix run lib/debug/test_image_download_with_flag.exs | tee -a $LOG_FILE

# Run the test for job argument propagation
echo "\n\n=== 2. Testing job argument propagation (without force refresh) ===" | tee -a $LOG_FILE
echo "Running: mix run test_force_refresh_flag.exs" | tee -a $LOG_FILE
mix run test_force_refresh_flag.exs | tee -a $LOG_FILE

# Run the test with force refresh
echo "\n\n=== 3. Testing job argument propagation (with force refresh) ===" | tee -a $LOG_FILE
echo "Running: mix run test_force_refresh_flag.exs --force-refresh" | tee -a $LOG_FILE
mix run test_force_refresh_flag.exs --force-refresh | tee -a $LOG_FILE

# Test the instrumented Oban job
echo "\n\n=== 4. Testing instrumented index job ===" | tee -a $LOG_FILE
echo "Running: mix run lib/debug/test_force_refresh_images_in_jobs.exs" | tee -a $LOG_FILE
mix run lib/debug/test_force_refresh_images_in_jobs.exs | tee -a $LOG_FILE

echo "\n\nAll tests completed. Results saved to $LOG_FILE"
echo "Check the file for 'Force refresh flag:' entries."