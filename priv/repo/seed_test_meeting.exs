user = SocialScribe.Repo.one(SocialScribe.Accounts.User |> Ecto.Query.first())

if is_nil(user) do
  IO.puts("ERROR: No users found. Log in via the app first.")
  System.halt(1)
end

IO.puts("Using user: #{user.email} (id: #{user.id})")

credential =
  SocialScribe.Repo.get_by(
    SocialScribe.Accounts.UserCredential,
    user_id: user.id,
    provider: "google"
  )

credential =
  credential ||
    SocialScribe.Repo.insert!(%SocialScribe.Accounts.UserCredential{
      user_id: user.id,
      provider: "google",
      uid: "seed_google_#{System.unique_integer([:positive])}",
      email: user.email,
      token: "fake_token",
      refresh_token: "fake_refresh",
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })

{:ok, calendar_event} =
  SocialScribe.Calendar.create_calendar_event(%{
    google_event_id: "seed_event_#{System.unique_integer([:positive])}",
    summary: "Product Sync with Jane Smith",
    html_link: "https://calendar.google.com",
    status: "confirmed",
    start_time: DateTime.add(DateTime.utc_now(), -3600, :second),
    end_time: DateTime.utc_now(),
    user_id: user.id,
    user_credential_id: credential.id
  })

{:ok, recall_bot} =
  SocialScribe.Bots.create_recall_bot(%{
    recall_bot_id: "seed_bot_#{System.unique_integer([:positive])}",
    status: "done",
    meeting_url: "https://meet.google.com/abc-defg-hij",
    user_id: user.id,
    calendar_event_id: calendar_event.id
  })

{:ok, meeting} =
  SocialScribe.Meetings.create_meeting(%{
    title: "Product Sync with Jane Smith",
    recorded_at: DateTime.utc_now(),
    duration_seconds: 2700,
    calendar_event_id: calendar_event.id,
    recall_bot_id: recall_bot.id,
    follow_up_email:
      "Hi Jane,\n\nGreat meeting today! Here is a quick recap of what we discussed.\n\nBest,\nTeam"
  })

{:ok, _transcript} =
  SocialScribe.Meetings.create_meeting_transcript(%{
    meeting_id: meeting.id,
    language: "en",
    content: %{
      "data" => [
        %{
          "speaker" => "You",
          "words" => [
            %{"text" => "Hey"},
            %{"text" => "Jane,"},
            %{"text" => "thanks"},
            %{"text" => "for"},
            %{"text" => "joining."}
          ]
        },
        %{
          "speaker" => "Jane Smith",
          "words" => [
            %{"text" => "Hi!"},
            %{"text" => "My"},
            %{"text" => "new"},
            %{"text" => "number"},
            %{"text" => "is"},
            %{"text" => "555-1234"},
            %{"text" => "and"},
            %{"text" => "I"},
            %{"text" => "moved"},
            %{"text" => "to"},
            %{"text" => "the"},
            %{"text" => "Engineering"},
            %{"text" => "department."}
          ]
        }
      ]
    }
  })

{:ok, _} =
  SocialScribe.Meetings.create_meeting_participant(%{
    meeting_id: meeting.id,
    recall_participant_id: "part_1",
    name: "You",
    is_host: true
  })

{:ok, _} =
  SocialScribe.Meetings.create_meeting_participant(%{
    meeting_id: meeting.id,
    recall_participant_id: "part_2",
    name: "Jane Smith",
    is_host: false
  })

# Ensure Salesforce credential exists
sf_cred =
  SocialScribe.Repo.get_by(
    SocialScribe.Accounts.UserCredential,
    user_id: user.id,
    provider: "salesforce"
  )

if is_nil(sf_cred) do
  SocialScribe.Repo.insert!(%SocialScribe.Accounts.UserCredential{
    user_id: user.id,
    provider: "salesforce",
    uid: "005_seed_#{System.unique_integer([:positive])}",
    email: user.email,
    refresh_token: "fake_sf_refresh",
    token: "fake_sf_token",
    instance_url: "https://test.salesforce.com",
    expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
  })

  IO.puts("Created Salesforce credential")
else
  IO.puts("Salesforce credential already exists")
end

IO.puts("\nDone! Visit: http://localhost:4000/dashboard/meetings/#{meeting.id}")
