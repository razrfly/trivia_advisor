import Ecto.Query
alias TriviaAdvisor.Scraping.Oban.InquizitionIndexJob
alias TriviaAdvisor.Scraping.Source
alias TriviaAdvisor.Repo
alias TriviaAdvisor.Locations.Venue

# First, let's see what venues we have in our database with these names
IO.puts("\n=== Problematic venue records ===\n")
problematic_venues = ["The White Horse", "The Mitre", "The Railway"]

for name <- problematic_venues do
  IO.puts("#{name} venues:")
  venues = Repo.all(from v in Venue, where: v.name == ^name or like(v.name, ^"#{name}%"))

  for v <- venues do
    IO.puts("  #{v.id}: #{v.name} - #{v.address} - Postcode: #{v.postcode || "None"}")
  end
  IO.puts("")
end

# Now run the job
IO.puts("\n=== Running job for \"inquizition\" source ===\n")
source = Repo.get_by!(Source, name: "inquizition")
{:ok, result} = InquizitionIndexJob.perform(%Oban.Job{args: %{"limit" => nil}, id: 999999})
IO.puts("Job Result: #{inspect(result)}")
