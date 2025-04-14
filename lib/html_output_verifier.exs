#!/usr/bin/env elixir

defmodule HtmlOutputVerifier do
  @moduledoc """
  Script to compare HTML output between branches to ensure refactored code produces identical output.

  ## Usage:

  ```
  mix run lib/html_output_verifier.exs
  ```

  This script:
  1. Captures HTML output for specified pages in current branch
  2. Switches to main branch, captures output again
  3. Compares outputs and reports differences
  4. Switches back to original branch
  """

  @pages_to_verify [
    "/venues/example-venue-slug",
    "/cities/example-city-slug"
  ]

  def run do
    IO.puts("HTML Output Verification Script")
    IO.puts("===============================")

    # Get current branch name
    {current_branch, 0} = System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"])
    current_branch = String.trim(current_branch)

    IO.puts("Current branch: #{current_branch}")

    # Start the Phoenix server in test mode
    Mix.Task.run("phx.server")

    # Allow time for server to start
    :timer.sleep(2000)

    # Capture HTML in current branch
    current_branch_html = capture_html_for_pages()

    # Stop the server
    Application.stop(:trivia_advisor)
    :timer.sleep(1000)

    # Switch to main branch
    IO.puts("\nSwitching to main branch...")
    System.cmd("git", ["checkout", "main"])

    # Recompile and start the server
    Mix.Task.run("compile")
    Mix.Task.run("phx.server")

    # Allow time for server to start
    :timer.sleep(2000)

    # Capture HTML in main branch
    main_branch_html = capture_html_for_pages()

    # Stop the server
    Application.stop(:trivia_advisor)
    :timer.sleep(1000)

    # Switch back to original branch
    IO.puts("\nSwitching back to #{current_branch}...")
    System.cmd("git", ["checkout", current_branch])

    # Compare the HTML
    compare_results(current_branch_html, main_branch_html)
  end

  defp capture_html_for_pages do
    IO.puts("\nCapturing HTML for pages:")

    Enum.reduce(@pages_to_verify, %{}, fn page, acc ->
      IO.puts("  - #{page}")

      # Use HTTPoison to get the page content
      url = "http://localhost:4001#{page}"

      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          # Clean HTML by removing whitespace variations and comments
          clean_html = clean_html_for_comparison(body)
          Map.put(acc, page, clean_html)

        {:ok, %HTTPoison.Response{status_code: code}} ->
          IO.puts("    Error: Received status code #{code}")
          Map.put(acc, page, nil)

        {:error, %HTTPoison.Error{reason: reason}} ->
          IO.puts("    Error: #{reason}")
          Map.put(acc, page, nil)
      end
    end)
  end

  defp clean_html_for_comparison(html) do
    html
    |> String.replace(~r/<!--.*?-->/s, "") # Remove HTML comments
    |> String.replace(~r/\s+/s, " ")      # Normalize whitespace
    |> String.replace(~r/>\s+</s, "><")   # Remove whitespace between tags
    |> String.trim()                       # Trim leading/trailing whitespace
  end

  defp compare_results(current_html, main_html) do
    IO.puts("\nComparing HTML output:")

    Enum.each(@pages_to_verify, fn page ->
      current_page_html = Map.get(current_html, page)
      main_page_html = Map.get(main_html, page)

      cond do
        is_nil(current_page_html) or is_nil(main_page_html) ->
          IO.puts("  - #{page}: Unable to compare (failed to retrieve)")

        current_page_html == main_page_html ->
          IO.puts("  - #{page}: ✅ Match - HTML output is identical")

        true ->
          IO.puts("  - #{page}: ❌ Mismatch - HTML outputs differ")
          show_diff(page, current_page_html, main_page_html)
      end
    end)
  end

  defp show_diff(page, current_html, main_html) do
    # Create temp files for diffing
    current_file = Path.join(System.tmp_dir(), "current_#{Path.basename(page)}.html")
    main_file = Path.join(System.tmp_dir(), "main_#{Path.basename(page)}.html")

    File.write!(current_file, current_html)
    File.write!(main_file, main_html)

    # Run diff and display output
    {diff_output, _} = System.cmd("diff", ["-u", main_file, current_file])

    if String.length(diff_output) > 1000 do
      IO.puts("    Diff too large to display. Files saved at:")
      IO.puts("    - Current branch: #{current_file}")
      IO.puts("    - Main branch: #{main_file}")
    else
      IO.puts("\n--- Begin Diff ---")
      IO.puts(diff_output)
      IO.puts("--- End Diff ---\n")
    end
  end
end

# Run the verifier
HtmlOutputVerifier.run()
