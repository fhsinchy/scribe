defmodule SocialScribe.Chat do
  @moduledoc """
  The Chat context.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  alias SocialScribe.Chat.Conversation
  alias SocialScribe.Chat.Message

  ## Conversations

  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def list_user_conversations(user_id) do
    from(c in Conversation,
      where: c.user_id == ^user_id,
      order_by: [desc: c.updated_at],
      preload: []
    )
    |> Repo.all()
  end

  def get_conversation!(id) do
    Repo.get!(Conversation, id)
  end

  def get_conversation_with_messages!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(messages: from(m in Message, order_by: [asc: m.inserted_at]))
  end

  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  ## Messages

  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def list_conversation_messages(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end
end
