alias TriviaAdvisor.Repo
import Ecto.Query

jobs_stats = Repo.all(from j in "oban_jobs",
  where: j.worker == "TriviaAdvisor.Scraping.Oban.QuizmeistersDetailJob",
  group_by: [j.worker, j.state],
  select: {j.worker, j.state, count(j.id)})

total_jobs = Enum.reduce(jobs_stats, 0, fn {_, _, count}, acc -> acc + count end)

IO.puts("Oban job statistics for QuizmeistersDetailJob:")
IO.puts("Total jobs: #{total_jobs}")

Enum.each(jobs_stats, fn {worker, state, count} ->
  IO.puts("  #{state}: #{count}")
end)
