defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat

  import SocialScribe.ChatFixtures
  import SocialScribe.AccountsFixtures

  describe "conversations" do
    test "create_conversation/1 with valid data creates a conversation" do
      user = user_fixture()
      attrs = %{user_id: user.id, title: "My chat"}

      assert {:ok, conversation} = Chat.create_conversation(attrs)
      assert conversation.user_id == user.id
      assert conversation.title == "My chat"
    end

    test "create_conversation/1 without user_id returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Chat.create_conversation(%{title: "No user"})
    end

    test "list_user_conversations/1 returns conversations for a specific user" do
      user1 = user_fixture()
      user2 = user_fixture()

      conv1 = conversation_fixture(%{user_id: user1.id, title: "User 1 conv"})
      _conv2 = conversation_fixture(%{user_id: user2.id, title: "User 2 conv"})

      conversations = Chat.list_user_conversations(user1.id)
      assert length(conversations) == 1
      assert hd(conversations).id == conv1.id
    end

    test "list_user_conversations/1 returns conversations ordered by updated_at desc" do
      user = user_fixture()
      conv1 = conversation_fixture(%{user_id: user.id, title: "First"})

      # Ensure different timestamps (utc_datetime has second precision)
      :timer.sleep(1100)
      conv2 = conversation_fixture(%{user_id: user.id, title: "Second"})

      conversations = Chat.list_user_conversations(user.id)
      assert length(conversations) == 2
      assert hd(conversations).id == conv2.id
      assert List.last(conversations).id == conv1.id
    end

    test "get_conversation!/1 returns the conversation with given id" do
      conversation = conversation_fixture()
      assert Chat.get_conversation!(conversation.id).id == conversation.id
    end

    test "get_conversation_with_messages!/1 returns conversation with preloaded messages" do
      conversation = conversation_fixture()
      _msg1 = message_fixture(%{conversation_id: conversation.id, content: "Hello"})

      _msg2 =
        message_fixture(%{conversation_id: conversation.id, role: "assistant", content: "Hi"})

      loaded = Chat.get_conversation_with_messages!(conversation.id)
      assert length(loaded.messages) == 2
      assert hd(loaded.messages).content == "Hello"
    end

    test "delete_conversation/1 deletes the conversation" do
      conversation = conversation_fixture()
      assert {:ok, %Chat.Conversation{}} = Chat.delete_conversation(conversation)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_conversation!(conversation.id) end
    end

    test "delete_conversation/1 cascades to messages" do
      conversation = conversation_fixture()
      message = message_fixture(%{conversation_id: conversation.id})

      assert {:ok, _} = Chat.delete_conversation(conversation)
      assert Chat.list_conversation_messages(conversation.id) == []
      assert_raise Ecto.NoResultsError, fn -> Repo.get!(Chat.Message, message.id) end
    end
  end

  describe "messages" do
    test "create_message/1 with valid data creates a message" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        role: "user",
        content: "What about Tim?",
        metadata: %{"tagged_contacts" => [%{"id" => "123", "name" => "Tim", "crm" => "hubspot"}]}
      }

      assert {:ok, message} = Chat.create_message(attrs)
      assert message.role == "user"
      assert message.content == "What about Tim?"
      assert message.metadata["tagged_contacts"] != nil
    end

    test "create_message/1 with assistant role works" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        role: "assistant",
        content: "Here's what I found...",
        metadata: %{"sources" => [%{"crm" => "hubspot", "contact_name" => "Tim"}]}
      }

      assert {:ok, message} = Chat.create_message(attrs)
      assert message.role == "assistant"
    end

    test "create_message/1 with invalid role returns error changeset" do
      conversation = conversation_fixture()

      attrs = %{
        conversation_id: conversation.id,
        role: "system",
        content: "Invalid role"
      }

      assert {:error, %Ecto.Changeset{}} = Chat.create_message(attrs)
    end

    test "create_message/1 without content returns error changeset" do
      conversation = conversation_fixture()
      attrs = %{conversation_id: conversation.id, role: "user"}

      assert {:error, %Ecto.Changeset{}} = Chat.create_message(attrs)
    end

    test "list_conversation_messages/1 returns messages ordered by inserted_at" do
      conversation = conversation_fixture()
      msg1 = message_fixture(%{conversation_id: conversation.id, content: "First"})

      :timer.sleep(10)
      msg2 = message_fixture(%{conversation_id: conversation.id, content: "Second"})

      messages = Chat.list_conversation_messages(conversation.id)
      assert length(messages) == 2
      assert hd(messages).id == msg1.id
      assert List.last(messages).id == msg2.id
    end

    test "messages are isolated to their conversation" do
      conv1 = conversation_fixture()
      conv2 = conversation_fixture()

      _msg1 = message_fixture(%{conversation_id: conv1.id, content: "Conv 1 msg"})
      _msg2 = message_fixture(%{conversation_id: conv2.id, content: "Conv 2 msg"})

      messages = Chat.list_conversation_messages(conv1.id)
      assert length(messages) == 1
      assert hd(messages).content == "Conv 1 msg"
    end
  end
end
