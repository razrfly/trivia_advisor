#!/usr/bin/env elixir

# Simple script to check Google Maps API key configuration

IO.puts("Checking Google Maps API key configuration...\n")

# Check environment variable
api_key_env = System.get_env("GOOGLE_MAPS_API_KEY")
if is_nil(api_key_env) or api_key_env == "" do
  IO.puts("❌ GOOGLE_MAPS_API_KEY environment variable is not set")
else
  IO.puts("✅ GOOGLE_MAPS_API_KEY environment variable is set to: #{String.slice(api_key_env, 0, 5)}...")
end

# Show how to set it
IO.puts("\nTo set the API key in your current shell:")
IO.puts("  export GOOGLE_MAPS_API_KEY=your_actual_api_key_here")
IO.puts("\nTo set it permanently, add it to your shell profile file (~/.bashrc, ~/.zshrc, etc.)")
IO.puts("\nTo set it for a single command:")
IO.puts("  GOOGLE_MAPS_API_KEY=your_api_key mix sync_venue_images")

# Instructions for .env file
IO.puts("\nAlternatively, you can create a .env file in the project root:")
IO.puts("  echo \"GOOGLE_MAPS_API_KEY=your_api_key\" > .env")
IO.puts("  source .env  # Run this before starting the application\n")

# Checking config file
IO.puts("Checking config files...")
try do
  # Try to load the configuration, this will require Mix to be available
  Mix.start()
  Mix.loadpaths()
  config = Application.get_env(:trivia_advisor, TriviaAdvisor.Scraping.GoogleAPI)
  if config do
    IO.puts("✅ Configuration found in Application env: #{inspect(config)}")
  else
    IO.puts("❌ No configuration found in Application env")
  end
rescue
  _ -> IO.puts("⚠️ Couldn't check application config (Mix environment not available)")
end
