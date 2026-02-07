defmodule SocialScribe.Chat.Message do
  @moduledoc """
  Schema for chat messages. Each message belongs to a conversation and has a role (user or assistant).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.Conversation

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :conversation, Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :metadata])
    |> validate_required([:conversation_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
    |> foreign_key_constraint(:conversation_id)
  end
end
