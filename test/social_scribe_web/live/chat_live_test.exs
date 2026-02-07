defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.ChatFixtures
  import Mox

  setup :verify_on_exit!

  describe "ChatLive without CRM" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "renders chat page with title and tabs", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "Ask Anything"
      assert has_element?(view, "button", "Chat")
      assert has_element?(view, "button", "History")
    end

    test "shows intro message when no messages", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "I can answer questions about your contacts"
    end

    test "shows no CRM connected warning", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "No CRM connected"
    end

    test "switches between Chat and History tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Switch to history
      html = view |> element("button", "History") |> render_click()
      assert html =~ "No chat history yet"

      # Switch back to chat
      html = view |> element("button", "Chat") |> render_click()
      assert html =~ "I can answer questions about your contacts"
    end

    test "sends message and receives AI response", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn query, _context ->
        assert query =~ "Hello"
        {:ok, "Hi there! How can I help you?"}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Send a message
      view |> render_hook("send_message", %{"content" => "Hello AI"})

      # User message should appear
      html = render(view)
      assert html =~ "Hello AI"

      # Wait for async response
      :timer.sleep(100)
      html = render(view)
      assert html =~ "Hi there! How can I help you?"
    end

    test "new chat resets state", %{conn: conn, user: user} do
      conversation = conversation_fixture(%{user_id: user.id, title: "Old chat"})

      message_fixture(%{
        conversation_id: conversation.id,
        content: "Old message"
      })

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat/#{conversation.id}")

      html = render(view)
      assert html =~ "Old message"

      # Click new chat
      view |> element("button[title='New chat']") |> render_click()

      html = render(view)
      assert html =~ "I can answer questions about your contacts"
      refute html =~ "Old message"
    end

    test "loads existing conversation from history", %{conn: conn, user: user} do
      conversation = conversation_fixture(%{user_id: user.id, title: "Past chat"})
      message_fixture(%{conversation_id: conversation.id, content: "History message"})

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Switch to history
      view |> element("button", "History") |> render_click()

      html = render(view)
      assert html =~ "Past chat"

      # Click on conversation
      view |> element("button[phx-click='select_conversation']") |> render_click()

      html = render(view)
      assert html =~ "History message"
    end

    test "history shows empty state when no conversations", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> element("button", "History") |> render_click()

      html = render(view)
      assert html =~ "No chat history yet"
    end

    test "handles AI error gracefully", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _context ->
        {:error, :api_error}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("send_message", %{"content" => "Hello"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "I&#39;m sorry, I wasn&#39;t able to generate a response"
    end

    test "sending empty message is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("send_message", %{"content" => ""})

      html = render(view)
      # Still showing intro, no conversation created
      assert html =~ "I can answer questions about your contacts"
    end

    test "sending whitespace-only message is a no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("send_message", %{"content" => "   "})

      html = render(view)
      assert html =~ "I can answer questions about your contacts"
    end

    test "delete_conversation removes from history", %{conn: conn, user: user} do
      conversation = conversation_fixture(%{user_id: user.id, title: "To delete"})

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Switch to history
      view |> element("button", "History") |> render_click()
      html = render(view)
      assert html =~ "To delete"

      # Delete the conversation
      view |> render_hook("delete_conversation", %{"id" => to_string(conversation.id)})

      html = render(view)
      refute html =~ "To delete"
    end

    test "delete_conversation resets if current conversation is deleted", %{
      conn: conn,
      user: user
    } do
      conversation = conversation_fixture(%{user_id: user.id, title: "Current chat"})
      message_fixture(%{conversation_id: conversation.id, content: "Some message"})

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat/#{conversation.id}")

      html = render(view)
      assert html =~ "Some message"

      # Delete the current conversation
      view |> render_hook("delete_conversation", %{"id" => to_string(conversation.id)})

      html = render(view)
      # Messages should be cleared
      refute html =~ "Some message"
    end

    test "conversation auto-titles from first message", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _context ->
        {:ok, "Sure, here is some info."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("send_message", %{"content" => "What is the weather today?"})

      :timer.sleep(100)

      # Switch to history to see the auto-titled conversation
      view |> element("button", "History") |> render_click()
      html = render(view)
      assert html =~ "What is the weather today?"
    end

    test "multiple messages reuse the same conversation", %{conn: conn} do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, 2, fn _query, _context ->
        {:ok, "AI response"}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Send first message
      view |> render_hook("send_message", %{"content" => "First message"})
      :timer.sleep(100)

      # Send second message
      view |> render_hook("send_message", %{"content" => "Second message"})
      :timer.sleep(100)

      html = render(view)
      assert html =~ "First message"
      assert html =~ "Second message"

      # Verify only one conversation was created
      conversations =
        SocialScribe.Chat.list_user_conversations(
          hd(SocialScribe.Repo.all(SocialScribe.Accounts.User)).id
        )

      assert length(conversations) == 1
    end
  end

  describe "ChatLive with HubSpot" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_credential = hubspot_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        hubspot_credential: hubspot_credential
      }
    end

    test "shows HubSpot as connected CRM source", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "HubSpot"
    end

    test "shows mention hint when HubSpot connected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "@name"
      assert html =~ "tag a contact"
    end

    test "contact @mention search returns results", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Tim"

        {:ok,
         [
           %{
             id: "101",
             firstname: "Tim",
             lastname: "Cook",
             email: "tim@apple.com",
             display_name: "Tim Cook"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Trigger mention search
      view |> render_hook("search_contacts_for_mention", %{"query" => "Tim"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Tim Cook"
    end

    test "tagging a contact sets context", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view
      |> render_hook("tag_contact", %{"id" => "101", "name" => "Tim Cook", "crm" => "hubspot"})

      html = render(view)
      assert html =~ "Tim Cook"
      assert html =~ "Asking about"
    end

    test "clear mention search clears results", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _credential, _query ->
        {:ok, [%{id: "101", firstname: "Tim", lastname: "Cook", display_name: "Tim Cook"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("search_contacts_for_mention", %{"query" => "Tim"})
      :timer.sleep(100)

      html = render(view)
      assert html =~ "Tim Cook"

      view |> render_hook("clear_mention_search", %{})
      html = render(view)
      refute html =~ "Tim Cook"
    end

    test "sends message with tagged contact and receives response", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _credential, "101" ->
        {:ok,
         %{
           id: "101",
           firstname: "Tim",
           lastname: "Cook",
           email: "tim@apple.com",
           display_name: "Tim Cook"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn query, context ->
        assert query =~ "Tell me about @Tim Cook"
        assert context[:crm] == :hubspot
        {:ok, "Tim Cook is a contact in your HubSpot CRM."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Tag a contact
      view
      |> render_hook("tag_contact", %{"id" => "101", "name" => "Tim Cook", "crm" => "hubspot"})

      # Send message
      view |> render_hook("send_message", %{"content" => "Tell me about @Tim Cook"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Tim Cook is a contact in your HubSpot CRM."
    end
  end

  describe "ChatLive with Salesforce" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        salesforce_credential: salesforce_credential
      }
    end

    test "shows Salesforce as connected CRM source", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "Salesforce"
    end

    test "contact search uses Salesforce API", %{conn: conn} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _credential, query ->
        assert query == "Jane"

        {:ok,
         [
           %{id: "SF001", firstname: "Jane", lastname: "Smith", display_name: "Jane Smith"}
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("search_contacts_for_mention", %{"query" => "Jane"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Jane Smith"
    end

    test "shows mention hint when Salesforce connected", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "@name"
      assert html =~ "tag a contact"
    end

    test "tagging a Salesforce contact sets context", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view
      |> render_hook("tag_contact", %{
        "id" => "SF001",
        "name" => "Jane Smith",
        "crm" => "salesforce"
      })

      html = render(view)
      assert html =~ "Jane Smith"
      assert html =~ "Asking about"
    end

    test "sends message with tagged Salesforce contact and receives response", %{conn: conn} do
      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _credential, "SF001" ->
        {:ok,
         %{
           id: "SF001",
           firstname: "Jane",
           lastname: "Smith",
           email: "jane@example.com",
           display_name: "Jane Smith"
         }}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn query, context ->
        assert query =~ "Tell me about @Jane Smith"
        assert context[:crm] == :salesforce
        {:ok, "Jane Smith is a contact in your Salesforce CRM."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Tag the contact
      view
      |> render_hook("tag_contact", %{
        "id" => "SF001",
        "name" => "Jane Smith",
        "crm" => "salesforce"
      })

      # Send message
      view |> render_hook("send_message", %{"content" => "Tell me about @Jane Smith"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Jane Smith is a contact in your Salesforce CRM."
    end
  end
end
