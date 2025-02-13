defmodule TriviaAdvisor.Events.EventTest do
  use ExUnit.Case
  alias TriviaAdvisor.Events.Event

  describe "parse_frequency/1" do
    test "handles weekly variations" do
      assert Event.parse_frequency("every week") == :weekly
      assert Event.parse_frequency("WEEKLY") == :weekly
      assert Event.parse_frequency("  each week  ") == :weekly
    end

    test "handles biweekly variations" do
      assert Event.parse_frequency("every 2 weeks") == :biweekly
      assert Event.parse_frequency("bi-weekly") == :biweekly
      assert Event.parse_frequency("biweekly") == :biweekly
      assert Event.parse_frequency("fortnightly") == :biweekly
    end

    test "handles monthly variations" do
      assert Event.parse_frequency("every month") == :monthly
      assert Event.parse_frequency("Monthly") == :monthly
    end

    test "handles irregular cases" do
      assert Event.parse_frequency("") == :irregular
      assert Event.parse_frequency("   ") == :irregular
      assert Event.parse_frequency("random text") == :irregular
      assert Event.parse_frequency(nil) == :irregular
      assert Event.parse_frequency(123) == :irregular
    end
  end
end
