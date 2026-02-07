defmodule SocialScribeWeb.SalesforceModalMoxTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  describe "Salesforce Modal with mocked API" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "search_contacts returns mocked results", %{conn: conn, meeting: meeting} do
      mock_contacts = [
        %{
          id: "SF001",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          company: "Acme Corp",
          display_name: "John Doe"
        },
        %{
          id: "SF002",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@example.com",
          phone: "555-1234",
          company: "Tech Inc",
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "John"
        {:ok, mock_contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Trigger contact search
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      # Wait for async update
      :timer.sleep(200)

      # Re-render to see updates
      html = render(view)

      # Verify contacts are displayed
      assert html =~ "John Doe"
      assert html =~ "Jane Smith"
    end

    test "search_contacts handles API error gracefully", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, %{"message" => "Internal server error"}}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      :timer.sleep(200)

      html = render(view)

      # Should show error message
      assert html =~ "Failed to search contacts"
    end

    test "selecting contact triggers suggestion generation", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "SF001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        company: "Acme Corp",
        display_name: "John Doe"
      }

      mock_suggestions = [
        %{
          field: "Phone",
          value: "555-1234",
          context: "Mentioned phone number"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [mock_contact]}
      end)

      # Mock the AI content generator for Salesforce suggestions
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, opts ->
        assert Keyword.get(opts, :crm) == :salesforce
        {:ok, mock_suggestions}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search for contact
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      # Select the contact
      view
      |> element("button[phx-click='select_contact'][phx-value-id='SF001']")
      |> render_click()

      :timer.sleep(500)

      # After selecting contact, suggestions should be generated
      # Modal should still be present
      assert has_element?(view, "#salesforce-modal-wrapper")
    end

    test "contact dropdown shows search results", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "SF789",
        firstname: "Test",
        lastname: "User",
        email: "test@example.com",
        phone: nil,
        company: nil,
        display_name: "Test User"
      }

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [mock_contact]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      :timer.sleep(200)

      html = render(view)

      # Verify contact appears in dropdown
      assert html =~ "Test User"
      assert html =~ "test@example.com"
    end

    test "applying updates successfully flashes and redirects", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "SF001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        company: "Acme Corp",
        display_name: "John Doe"
      }

      mock_suggestions = [
        %{
          field: "phone",
          value: "555-9876",
          context: "Mentioned phone number during call"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query -> {:ok, [mock_contact]} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, opts ->
        assert Keyword.get(opts, :crm) == :salesforce
        {:ok, mock_suggestions}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _credential, contact_id, updates ->
        assert contact_id == "SF001"
        assert Map.has_key?(updates, "phone")
        {:ok, %{id: "SF001", phone: "555-9876"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search for contact
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      # Select the contact
      view
      |> element("button[phx-click='select_contact'][phx-value-id='SF001']")
      |> render_click()

      :timer.sleep(500)

      # Suggestions should be rendered with the form
      html = render(view)
      assert html =~ "Phone"
      assert html =~ "Update Salesforce"

      # Submit the form with the phone suggestion selected
      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "555-9876"}
      })

      :timer.sleep(200)

      # Should redirect back to meeting page with success flash
      assert_patch(view, ~p"/dashboard/meetings/#{meeting.id}")
      html = render(view)
      assert html =~ "Successfully updated"
      assert html =~ "Salesforce"
    end

    test "applying updates handles API error", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "SF001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        company: "Acme Corp",
        display_name: "John Doe"
      }

      mock_suggestions = [
        %{
          field: "phone",
          value: "555-9876",
          context: "Mentioned phone number"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query -> {:ok, [mock_contact]} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, _opts -> {:ok, mock_suggestions} end)

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _credential, _contact_id, _updates ->
        {:error, {:api_error, 400, %{"message" => "Invalid field value"}}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search and select contact
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='SF001']")
      |> render_click()

      :timer.sleep(500)

      # Submit the form
      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"phone" => "1"},
        "values" => %{"phone" => "555-9876"}
      })

      :timer.sleep(200)

      # Should show error in the modal
      html = render(view)
      assert html =~ "Failed to update contact"
    end

    test "suggestion generation error shows error message", %{conn: conn, meeting: meeting} do
      mock_contact = %{
        id: "SF001",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        company: "Acme Corp",
        display_name: "John Doe"
      }

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, _query -> {:ok, [mock_contact]} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, _opts ->
        {:error, :ai_service_unavailable}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search for contact
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      # Select the contact - this triggers suggestion generation which will fail
      view
      |> element("button[phx-click='select_contact'][phx-value-id='SF001']")
      |> render_click()

      :timer.sleep(500)

      # Should show suggestion generation error
      html = render(view)
      assert html =~ "Failed to generate suggestions"
    end
  end

  describe "Salesforce API behavior delegation" do
    setup do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      %{credential: credential}
    end

    test "search_contacts delegates to implementation", %{credential: credential} do
      expected = [%{id: "SF1", firstname: "Test", lastname: "User"}]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.search_contacts(credential, "test query")
    end

    test "get_contact delegates to implementation", %{credential: credential} do
      expected = %{id: "SF123", firstname: "John", lastname: "Doe"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "SF123"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.get_contact(credential, "SF123")
    end

    test "update_contact delegates to implementation", %{credential: credential} do
      updates = %{"Phone" => "555-1234", "Department" => "Engineering"}
      expected = %{id: "SF123", phone: "555-1234", department: "Engineering"}

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, contact_id, upd ->
        assert contact_id == "SF123"
        assert upd == updates
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.update_contact(credential, "SF123", updates)
    end

    test "apply_updates delegates to implementation", %{credential: credential} do
      updates_list = [
        %{field: "Phone", new_value: "555-1234", apply: true},
        %{field: "Email", new_value: "test@example.com", apply: false}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:apply_updates, fn _cred, contact_id, list ->
        assert contact_id == "SF123"
        assert list == updates_list
        {:ok, %{id: "SF123"}}
      end)

      assert {:ok, _} =
               SocialScribe.SalesforceApiBehaviour.apply_updates(
                 credential,
                 "SF123",
                 updates_list
               )
    end
  end

  describe "Salesforce integration card on meeting page" do
    test "shows card when salesforce credential exists", %{conn: conn} do
      user = user_fixture()
      _salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      assert html =~ "Salesforce Integration"
      assert html =~ "Update Salesforce Contact"
    end

    test "hides card when no salesforce credential exists", %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Salesforce Integration"
      refute html =~ "Update Salesforce Contact"
    end
  end

  # Helper function to create a meeting with transcript for testing
  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,"},
              %{"text" => "my"},
              %{"text" => "phone"},
              %{"text" => "is"},
              %{"text" => "555-1234"}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
