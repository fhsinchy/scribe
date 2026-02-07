defmodule SocialScribe.ChatPropertyTest do
  use SocialScribe.DataCase, async: true
  use ExUnitProperties

  import SocialScribe.AccountsFixtures

  alias SocialScribe.Chat

  describe "Message changeset properties" do
    setup do
      user = user_fixture()
      {:ok, conversation} = Chat.create_conversation(%{user_id: user.id})
      %{conversation: conversation}
    end

    property "messages with invalid role always fail validation", %{conversation: conversation} do
      check all(
              role <- invalid_role_generator(),
              content <- content_generator()
            ) do
        changeset =
          SocialScribe.Chat.Message.changeset(%SocialScribe.Chat.Message{}, %{
            conversation_id: conversation.id,
            role: role,
            content: content
          })

        refute changeset.valid?,
               "Role #{inspect(role)} should be invalid"
      end
    end

    property "messages with valid role and content always pass validation", %{
      conversation: conversation
    } do
      check all(
              role <- member_of(["user", "assistant"]),
              content <- content_generator()
            ) do
        changeset =
          SocialScribe.Chat.Message.changeset(%SocialScribe.Chat.Message{}, %{
            conversation_id: conversation.id,
            role: role,
            content: content
          })

        assert changeset.valid?,
               "Role #{inspect(role)} with content #{inspect(content)} should be valid"
      end
    end
  end

  describe "Conversation changeset properties" do
    property "conversations always require a user_id" do
      check all(title <- one_of([constant(nil), string(:alphanumeric, min_length: 1)])) do
        changeset =
          SocialScribe.Chat.Conversation.changeset(%SocialScribe.Chat.Conversation{}, %{
            title: title
          })

        refute changeset.valid?,
               "Conversation without user_id should be invalid"

        assert %{user_id: ["can't be blank"]} = errors_on(changeset)
      end
    end
  end

  describe "Message isolation properties" do
    setup do
      user = user_fixture()
      {:ok, conv_a} = Chat.create_conversation(%{user_id: user.id})
      {:ok, conv_b} = Chat.create_conversation(%{user_id: user.id})
      %{conv_a: conv_a, conv_b: conv_b}
    end

    property "created messages always belong to their conversation", %{
      conv_a: conv_a,
      conv_b: conv_b
    } do
      check all(
              content_a <- content_generator(),
              content_b <- content_generator()
            ) do
        {:ok, msg_a} =
          Chat.create_message(%{
            conversation_id: conv_a.id,
            role: "user",
            content: content_a
          })

        {:ok, msg_b} =
          Chat.create_message(%{
            conversation_id: conv_b.id,
            role: "assistant",
            content: content_b
          })

        messages_a = Chat.list_conversation_messages(conv_a.id)
        messages_b = Chat.list_conversation_messages(conv_b.id)

        assert Enum.any?(messages_a, &(&1.id == msg_a.id)),
               "Message A should appear in conversation A"

        refute Enum.any?(messages_a, &(&1.id == msg_b.id)),
               "Message B should NOT appear in conversation A"

        assert Enum.any?(messages_b, &(&1.id == msg_b.id)),
               "Message B should appear in conversation B"

        refute Enum.any?(messages_b, &(&1.id == msg_a.id)),
               "Message A should NOT appear in conversation B"
      end
    end
  end

  # Generators

  defp invalid_role_generator do
    filter(
      string(:alphanumeric, min_length: 1, max_length: 20),
      fn role -> role not in ["user", "assistant"] end
    )
  end

  defp content_generator do
    string(:alphanumeric, min_length: 1, max_length: 100)
  end
end
