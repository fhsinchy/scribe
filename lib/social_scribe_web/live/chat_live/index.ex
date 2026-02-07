defmodule SocialScribeWeb.ChatLive.Index do
  use SocialScribeWeb, :live_view

  require Logger

  alias SocialScribe.Accounts
  alias SocialScribe.Chat
  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApiBehaviour
  alias SocialScribe.SalesforceApiBehaviour

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {crm_provider, crm_credential} = detect_crm(user.id)
    conversations = Chat.list_user_conversations(user.id)

    socket =
      socket
      |> assign(:page_title, "Ask Anything")
      |> assign(:conversations, conversations)
      |> assign(:current_conversation, nil)
      |> assign(:messages, [])
      |> assign(:crm_provider, crm_provider)
      |> assign(:crm_credential, crm_credential)
      |> assign(:active_tab, :chat)
      |> assign(:tagged_contact, nil)
      |> assign(:contact_search_results, [])
      |> assign(:mention_query, nil)
      |> assign(:loading_response, false)
      |> assign(:searching_contacts, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"conversation_id" => id}, _uri, socket) do
    conversation = Chat.get_conversation_with_messages!(id)

    if conversation.user_id == socket.assigns.current_user.id do
      {:noreply,
       socket
       |> assign(:current_conversation, conversation)
       |> assign(:messages, conversation.messages)
       |> assign(:active_tab, :chat)}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Conversation not found")
       |> push_navigate(to: ~p"/dashboard/chat")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:current_conversation, nil)
     |> assign(:messages, [])
     |> assign(:tagged_contact, nil)}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      user = socket.assigns.current_user

      # Create or reuse conversation
      conversation =
        case socket.assigns.current_conversation do
          nil ->
            {:ok, conv} = Chat.create_conversation(%{user_id: user.id})
            conv

          conv ->
            conv
        end

      # Capture tagged contact before clearing
      tagged_contact = socket.assigns.tagged_contact

      # Build metadata with tagged contact info
      metadata = build_user_message_metadata(tagged_contact)

      # Save user message
      {:ok, user_msg} =
        Chat.create_message(%{
          conversation_id: conversation.id,
          role: "user",
          content: content,
          metadata: metadata
        })

      messages = socket.assigns.messages ++ [user_msg]

      # Trigger async AI response with captured tagged contact
      send(self(), {:generate_ai_response, conversation, user_msg, tagged_contact})

      {:noreply,
       socket
       |> assign(:current_conversation, conversation)
       |> assign(:messages, messages)
       |> assign(:loading_response, true)
       |> assign(:tagged_contact, nil)
       |> assign(:contact_search_results, [])
       |> assign(:mention_query, nil)
       |> push_patch_if_new_conversation(conversation)}
    end
  end

  def handle_event("new_chat", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_conversation, nil)
     |> assign(:messages, [])
     |> assign(:tagged_contact, nil)
     |> assign(:contact_search_results, [])
     |> assign(:mention_query, nil)
     |> assign(:loading_response, false)
     |> push_patch(to: ~p"/dashboard/chat")}
  end

  def handle_event("select_conversation", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/dashboard/chat/#{id}")}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    active_tab = if tab == "history", do: :history, else: :chat
    conversations = Chat.list_user_conversations(socket.assigns.current_user.id)

    {:noreply,
     socket
     |> assign(:active_tab, active_tab)
     |> assign(:conversations, conversations)}
  end

  def handle_event("search_contacts_for_mention", %{"query" => query}, socket) do
    send(self(), {:crm_contact_search, query})
    {:noreply, assign(socket, :mention_query, query)}
  end

  def handle_event("clear_mention_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:contact_search_results, [])
     |> assign(:mention_query, nil)}
  end

  def handle_event("tag_contact", %{"id" => id, "name" => name, "crm" => crm}, socket) do
    tagged_contact = %{id: id, name: name, crm: crm}

    {:noreply,
     socket
     |> assign(:tagged_contact, tagged_contact)
     |> assign(:contact_search_results, [])
     |> assign(:mention_query, nil)
     |> push_event("contact_tagged", %{name: name})}
  end

  def handle_event("delete_conversation", %{"id" => id}, socket) do
    conversation = Chat.get_conversation!(id)

    if conversation.user_id == socket.assigns.current_user.id do
      {:ok, _} = Chat.delete_conversation(conversation)
      conversations = Chat.list_user_conversations(socket.assigns.current_user.id)

      socket =
        if socket.assigns.current_conversation &&
             socket.assigns.current_conversation.id == conversation.id do
          socket
          |> assign(:current_conversation, nil)
          |> assign(:messages, [])
        else
          socket
        end

      {:noreply, assign(socket, :conversations, conversations)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:crm_contact_search, query}, socket) do
    credential = socket.assigns.crm_credential

    results =
      case {socket.assigns.crm_provider, credential} do
        {:hubspot, cred} when not is_nil(cred) ->
          case HubspotApiBehaviour.search_contacts(cred, query) do
            {:ok, contacts} -> format_contacts(contacts, "hubspot")
            _ -> []
          end

        {:salesforce, cred} when not is_nil(cred) ->
          case SalesforceApiBehaviour.search_contacts(cred, query) do
            {:ok, contacts} -> format_contacts(contacts, "salesforce")
            _ -> []
          end

        _ ->
          []
      end

    {:noreply, assign(socket, :contact_search_results, results)}
  end

  def handle_info({:generate_ai_response, conversation, user_msg, tagged_contact}, socket) do
    context = build_ai_context(socket, tagged_contact)

    response =
      case AIContentGeneratorApi.generate_chat_response(user_msg.content, context) do
        {:ok, text} ->
          text

        {:error, reason} ->
          Logger.error("Chat AI response failed: #{inspect(reason)}")
          "I'm sorry, I wasn't able to generate a response. Please try again."
      end

    # Build assistant metadata
    assistant_metadata = build_assistant_metadata(tagged_contact)

    {:ok, assistant_msg} =
      Chat.create_message(%{
        conversation_id: conversation.id,
        role: "assistant",
        content: response,
        metadata: assistant_metadata
      })

    # Auto-title from first user message if no title yet
    if is_nil(conversation.title) do
      title = user_msg.content |> String.slice(0, 50)

      title =
        if String.length(user_msg.content) > 50,
          do: title <> "...",
          else: title

      {:ok, updated_conv} =
        conversation
        |> SocialScribe.Chat.Conversation.changeset(%{title: title})
        |> SocialScribe.Repo.update()

      conversations = Chat.list_user_conversations(socket.assigns.current_user.id)

      {:noreply,
       socket
       |> assign(:messages, socket.assigns.messages ++ [assistant_msg])
       |> assign(:loading_response, false)
       |> assign(:current_conversation, updated_conv)
       |> assign(:conversations, conversations)}
    else
      {:noreply,
       socket
       |> assign(:messages, socket.assigns.messages ++ [assistant_msg])
       |> assign(:loading_response, false)}
    end
  end

  # Private helpers

  defp detect_crm(user_id) do
    case Accounts.get_user_hubspot_credential(user_id) do
      nil ->
        case Accounts.get_user_salesforce_credential(user_id) do
          nil -> {nil, nil}
          cred -> {:salesforce, cred}
        end

      cred ->
        {:hubspot, cred}
    end
  end

  defp build_user_message_metadata(nil), do: %{}

  defp build_user_message_metadata(tagged_contact) do
    %{"tagged_contacts" => [tagged_contact]}
  end

  defp build_assistant_metadata(nil), do: %{}

  defp build_assistant_metadata(tagged_contact) do
    %{"sources" => [%{"crm" => tagged_contact.crm, "contact_name" => tagged_contact.name}]}
  end

  defp build_ai_context(socket, tagged_contact) do
    contact_data =
      if tagged_contact do
        fetch_contact_data(tagged_contact, socket.assigns.crm_credential)
      else
        nil
      end

    %{
      contact: contact_data,
      crm: socket.assigns.crm_provider,
      conversation_history: socket.assigns.messages
    }
  end

  defp fetch_contact_data(%{crm: "hubspot", id: id}, credential) when not is_nil(credential) do
    case HubspotApiBehaviour.get_contact(credential, id) do
      {:ok, contact} -> contact
      _ -> nil
    end
  end

  defp fetch_contact_data(%{crm: "salesforce", id: id}, credential)
       when not is_nil(credential) do
    case SalesforceApiBehaviour.get_contact(credential, id) do
      {:ok, contact} -> contact
      _ -> nil
    end
  end

  defp fetch_contact_data(_, _), do: nil

  defp format_contacts(contacts, crm) do
    contacts
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn contact ->
      %{
        id: to_string(contact[:id] || ""),
        name: contact[:display_name] || "Unknown",
        crm: crm
      }
    end)
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(message) do
    Calendar.strftime(message.inserted_at, "%I:%M%P — %B %d, %Y")
  end

  defp format_date(nil), do: ""

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y")
  end

  defp push_patch_if_new_conversation(socket, conversation) do
    if socket.assigns.current_conversation &&
         socket.assigns.current_conversation.id == conversation.id do
      socket
    else
      push_patch(socket, to: ~p"/dashboard/chat/#{conversation.id}", replace: true)
    end
  end
end
