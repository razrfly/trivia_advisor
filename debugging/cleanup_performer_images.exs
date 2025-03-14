alias TriviaAdvisor.Tasks.PerformerImageCleanup

IO.puts("========================================")
IO.puts("🧹 Testing Performer Image Cleanup")
IO.puts("========================================")

# First, do a dry run to see what would be deleted
IO.puts("\n📋 Running in DRY RUN mode first...\n")
{:ok, stats} = PerformerImageCleanup.cleanup_duplicates(dry_run: true)

IO.puts("\n📊 Dry run statistics:")
IO.puts("  Directories checked: #{stats.directories_checked}")
IO.puts("  Directories with duplicates: #{stats.directories_with_duplicates}")
IO.puts("  Files that would be removed: #{stats.files_removed}")

# Ask if the user wants to proceed with actual cleanup
IO.puts("\n❓ Do you want to proceed with the actual cleanup? (y/n)")
response = IO.gets("") |> String.trim() |> String.downcase()

if response == "y" do
  IO.puts("\n🧹 Running ACTUAL cleanup (files will be deleted)...\n")
  {:ok, stats} = PerformerImageCleanup.cleanup_duplicates(dry_run: false)

  IO.puts("\n📊 Cleanup statistics:")
  IO.puts("  Directories checked: #{stats.directories_checked}")
  IO.puts("  Directories with duplicates: #{stats.directories_with_duplicates}")
  IO.puts("  Files removed: #{stats.files_removed}")

  IO.puts("\n✅ Cleanup completed successfully!")
else
  IO.puts("\n❌ Cleanup cancelled by user")
end

# Check for S3 storage
if Application.get_env(:waffle, :storage) == Waffle.Storage.S3 do
  IO.puts("\n☁️ S3 storage detected")
  IO.puts("To clean up S3, you would need to run:")
  s3_bucket = Application.get_env(:waffle, :bucket) || "[your-bucket-name]"
  IO.puts("  aws s3 ls s3://#{s3_bucket}/uploads/performers/ --recursive")

  case PerformerImageCleanup.cleanup_s3_duplicates(dry_run: true) do
    {:ok, _} ->
      IO.puts("See above for S3 cleanup details")
    {:error, reason} ->
      IO.puts("⚠️ Error with S3 cleanup: #{reason}")
  end
else
  IO.puts("\n💾 Using local storage (not S3)")
end
