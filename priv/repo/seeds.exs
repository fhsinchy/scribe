# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# In production (Docker):
#
#     docker compose exec app /app/bin/social_scribe eval "SocialScribe.Seeds.run()"
#
# This seeds a demo user (webshookeng@gmail.com) with realistic meeting data
# so the evaluator can immediately see the full app experience upon login.

alias SocialScribe.Repo
alias SocialScribe.Accounts.User
alias SocialScribe.Accounts.UserCredential
alias SocialScribe.Calendar.CalendarEvent
alias SocialScribe.Meetings
alias SocialScribe.Automations

demo_email = System.get_env("SEED_EMAIL", "webshookeng@gmail.com")

# --- 1. Find or create demo user ---
user =
  case Repo.get_by(User, email: demo_email) do
    %User{} = u ->
      IO.puts("Found existing user: #{u.email}")
      u

    nil ->
      IO.puts("Creating demo user: #{demo_email}")

      %User{}
      |> User.oauth_registration_changeset(%{email: demo_email})
      |> Repo.insert!()
  end

# --- 2. Create a dummy Google credential (needed as FK for calendar events) ---
google_credential =
  case Repo.get_by(UserCredential, user_id: user.id, provider: "google") do
    %UserCredential{} = c ->
      IO.puts("Found existing Google credential")
      c

    nil ->
      IO.puts("Creating dummy Google credential")

      %UserCredential{}
      |> UserCredential.changeset(%{
        user_id: user.id,
        provider: "google",
        uid: "seed_google_#{System.unique_integer([:positive])}",
        token: "seed_token",
        refresh_token: "seed_refresh",
        email: demo_email,
        expires_at: DateTime.add(DateTime.utc_now(), 86400, :second)
      })
      |> Repo.insert!()
  end

# --- 3. Create calendar events with meetings ---
meetings_data = [
  %{
    summary: "Q1 Strategy Review with Client",
    hangout_link: "https://meet.google.com/abc-defg-hij",
    start_time: DateTime.add(DateTime.utc_now(), -3600 * 24 * 2, :second),
    duration: 2340,
    transcript: [
      %{
        "speaker" => "Farhan Chowdhury",
        "words" => [
          %{"text" => "Welcome everyone to the Q1 strategy review."},
          %{"text" => "Let's discuss our progress and plan for the next quarter."},
          %{"text" => "Our revenue grew by 23% this quarter which exceeded expectations."},
          %{"text" => "The new product launch contributed significantly to this growth."}
        ]
      },
      %{
        "speaker" => "Sarah Johnson",
        "words" => [
          %{"text" => "Thanks Farhan. From the marketing side, our campaign ROI was 4.2x."},
          %{"text" => "We should increase our digital ad spend by 15% next quarter."},
          %{"text" => "My phone number has changed, it's now 555-0142."},
          %{"text" => "Also my new email is sarah.johnson@newdomain.com."}
        ]
      },
      %{
        "speaker" => "Mike Chen",
        "words" => [
          %{"text" => "Engineering delivered all sprint goals on time."},
          %{"text" => "We're planning to hire two more senior developers."},
          %{"text" => "The infrastructure costs came in at $45,000 for the quarter."},
          %{"text" => "I can be reached at mike.chen@techcorp.io going forward."}
        ]
      }
    ],
    participants: [
      %{name: "Farhan Chowdhury", is_host: true},
      %{name: "Sarah Johnson", is_host: false},
      %{name: "Mike Chen", is_host: false}
    ],
    follow_up_email: """
    Hi team,

    Thank you for attending the Q1 Strategy Review. Here's a summary of our discussion:

    Key Highlights:
    - Revenue grew 23% this quarter, exceeding expectations
    - Marketing campaign ROI reached 4.2x
    - Engineering delivered all sprint goals on time
    - Infrastructure costs: $45,000 for the quarter

    Action Items:
    1. Increase digital ad spend by 15% for Q2
    2. Begin hiring process for two senior developers
    3. Schedule follow-up meeting for Q2 planning

    Contact Updates:
    - Sarah Johnson: New phone 555-0142, new email sarah.johnson@newdomain.com
    - Mike Chen: New email mike.chen@techcorp.io

    Best regards,
    Social Scribe AI
    """
  },
  %{
    summary: "Product Demo with Acme Corp",
    hangout_link: "https://meet.google.com/xyz-uvwx-yz",
    start_time: DateTime.add(DateTime.utc_now(), -3600 * 24, :second),
    duration: 1800,
    transcript: [
      %{
        "speaker" => "Farhan Chowdhury",
        "words" => [
          %{"text" => "Thanks for joining the demo today."},
          %{"text" => "I'll walk you through our platform's key features."},
          %{
            "text" =>
              "Our AI-powered analytics can process data 10x faster than traditional tools."
          },
          %{"text" => "Let me show you the dashboard integration."}
        ]
      },
      %{
        "speaker" => "Emily Davis",
        "words" => [
          %{
            "text" =>
              "This looks impressive. We've been looking for exactly this kind of solution."
          },
          %{"text" => "Our current system handles about 500,000 records per day."},
          %{"text" => "Can your platform scale to that volume?"},
          %{"text" => "My direct line is 555-0198 if you need to reach me."},
          %{"text" => "And my work email is emily.davis@acmecorp.com."}
        ]
      }
    ],
    participants: [
      %{name: "Farhan Chowdhury", is_host: true},
      %{name: "Emily Davis", is_host: false}
    ],
    follow_up_email: """
    Hi Emily,

    Thank you for taking the time to see our product demo today. It was great connecting with you.

    Key Points Discussed:
    - AI-powered analytics with 10x faster processing
    - Dashboard integration capabilities
    - Scalability for 500,000+ records per day

    Next Steps:
    1. I'll send over a detailed proposal by end of week
    2. We can schedule a technical deep-dive with your engineering team
    3. Trial access will be set up within 24 hours

    Feel free to reach out anytime if you have questions.

    Best regards,
    Social Scribe AI
    """
  },
  %{
    summary: "Weekly Team Standup",
    hangout_link: "https://meet.google.com/stu-vwxy-z12",
    start_time: DateTime.add(DateTime.utc_now(), -3600 * 4, :second),
    duration: 900,
    transcript: [
      %{
        "speaker" => "Farhan Chowdhury",
        "words" => [
          %{"text" => "Good morning everyone, let's do a quick round of updates."},
          %{"text" => "I finished the API integration yesterday and it's in code review."}
        ]
      },
      %{
        "speaker" => "Alex Rivera",
        "words" => [
          %{"text" => "I'm working on the new authentication module."},
          %{"text" => "Should be done by Thursday."},
          %{"text" => "Also, I moved to a new office, my new number is 555-0234."},
          %{"text" => "I'll be working from the San Francisco office now."}
        ]
      },
      %{
        "speaker" => "Lisa Park",
        "words" => [
          %{"text" => "Design mockups for the settings page are ready for review."},
          %{"text" => "I've uploaded them to Figma. Let me know your thoughts."},
          %{"text" => "My updated email is lisa.park@designhub.io."}
        ]
      }
    ],
    participants: [
      %{name: "Farhan Chowdhury", is_host: true},
      %{name: "Alex Rivera", is_host: false},
      %{name: "Lisa Park", is_host: false}
    ],
    follow_up_email: """
    Hi team,

    Here's a quick recap of today's standup:

    Updates:
    - Farhan: API integration complete, in code review
    - Alex: Authentication module in progress, ETA Thursday
    - Lisa: Settings page design mockups ready on Figma

    Contact Changes:
    - Alex Rivera: New phone 555-0234, now at SF office
    - Lisa Park: New email lisa.park@designhub.io

    Have a productive day!

    Best regards,
    Social Scribe AI
    """
  }
]

for meeting_data <- meetings_data do
  event_id = "seed_event_#{System.unique_integer([:positive])}"

  # Check if this meeting already exists (idempotent)
  existing =
    Repo.get_by(CalendarEvent,
      user_id: user.id,
      summary: meeting_data.summary,
      user_credential_id: google_credential.id
    )

  if existing do
    IO.puts("Skipping existing meeting: #{meeting_data.summary}")
  else
    IO.puts("Creating meeting: #{meeting_data.summary}")

    end_time = DateTime.add(meeting_data.start_time, meeting_data.duration, :second)

    # Calendar event
    {:ok, event} =
      SocialScribe.Calendar.create_calendar_event(%{
        google_event_id: event_id,
        summary: meeting_data.summary,
        description: "Seeded demo meeting",
        html_link: "#",
        hangout_link: meeting_data.hangout_link,
        status: "confirmed",
        start_time: meeting_data.start_time,
        end_time: end_time,
        record_meeting: true,
        user_id: user.id,
        user_credential_id: google_credential.id
      })

    # Recall bot
    {:ok, bot} =
      SocialScribe.Bots.create_recall_bot(%{
        recall_bot_id: "seed_bot_#{System.unique_integer([:positive])}",
        status: "done",
        meeting_url: meeting_data.hangout_link,
        user_id: user.id,
        calendar_event_id: event.id
      })

    # Meeting
    {:ok, meeting} =
      Meetings.create_meeting(%{
        title: meeting_data.summary,
        recorded_at: meeting_data.start_time,
        duration_seconds: meeting_data.duration,
        calendar_event_id: event.id,
        recall_bot_id: bot.id,
        follow_up_email: meeting_data.follow_up_email
      })

    # Transcript
    Meetings.create_meeting_transcript(%{
      meeting_id: meeting.id,
      content: %{"data" => meeting_data.transcript},
      language: "en"
    })

    # Participants
    for {participant, idx} <- Enum.with_index(meeting_data.participants) do
      Meetings.create_meeting_participant(%{
        meeting_id: meeting.id,
        name: participant.name,
        is_host: participant.is_host,
        recall_participant_id: "seed_participant_#{meeting.id}_#{idx}"
      })
    end
  end
end

# --- 4. Create a sample automation ---
case Automations.list_active_user_automations(user.id) do
  [] ->
    IO.puts("Creating sample automation")

    Automations.create_automation(%{
      user_id: user.id,
      name: "LinkedIn Post Generator",
      description: "Generates a professional LinkedIn post summarizing key meeting takeaways",
      example:
        "Based on the following meeting transcript, write a professional LinkedIn post (200-300 words) highlighting key insights and takeaways. Make it engaging and thought-provoking. Include relevant hashtags.\n\nMeeting: {{meeting_title}}\nTranscript: {{transcript}}",
      platform: "linkedin",
      is_active: true
    })

  _ ->
    IO.puts("Automations already exist, skipping")
end

IO.puts("\nSeed complete! Demo data ready for #{demo_email}")
