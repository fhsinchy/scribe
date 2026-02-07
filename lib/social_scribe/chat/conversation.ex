defmodule SocialScribe.Chat.Conversation do
  @moduledoc """
  Schema for chat conversations. Each conversation belongs to a user and has many messages.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.Message

  schema "chat_conversations" do
    field :title, :string

    belongs_to :user, User
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:user_id, :title])
    |> validate_required([:user_id])
    |> foreign_key_constraint(:user_id)
  end
end
