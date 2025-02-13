ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TriviaAdvisor.Repo, :manual)

# Define mocks
Mox.defmock(TriviaAdvisor.Scraping.MockGoogleLookup, for: TriviaAdvisor.Scraping.GoogleLookupBehaviour)
