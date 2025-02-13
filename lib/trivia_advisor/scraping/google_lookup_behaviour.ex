defmodule TriviaAdvisor.Scraping.GoogleLookupBehaviour do
  @callback lookup_address(String.t()) :: {:ok, map()} | {:error, String.t()}
end
