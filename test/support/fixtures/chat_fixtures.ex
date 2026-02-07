defmodule SocialScribe.ChatFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `SocialScribe.Chat` context.
  """

  import SocialScribe.AccountsFixtures

  def conversation_fixture(attrs \\ %{}) do
    user_id = attrs[:user_id] || user_fixture().id

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        user_id: user_id,
        title: "Test conversation"
      })
      |> SocialScribe.Chat.create_conversation()

    conversation
  end

  def message_fixture(attrs \\ %{}) do
    conversation_id = attrs[:conversation_id] || conversation_fixture().id

    {:ok, message} =
      attrs
      |> Enum.into(%{
        conversation_id: conversation_id,
        role: "user",
        content: "Test message",
        metadata: %{}
      })
      |> SocialScribe.Chat.create_message()

    message
  end
end
