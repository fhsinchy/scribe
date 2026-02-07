defmodule SocialScribe.AIContentGeneratorApiTest do
  use SocialScribe.DataCase, async: true

  import Mox

  setup :verify_on_exit!

  describe "generate_crm_suggestions/2 delegation" do
    test "delegates to configured implementation with options" do
      meeting = %{id: 1, transcript: "Some transcript"}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn m, opts ->
        assert m == meeting
        assert opts[:crm] == :salesforce
        {:ok, [%{field: "phone", new_value: "555-0100"}]}
      end)

      result =
        SocialScribe.AIContentGeneratorApi.generate_crm_suggestions(meeting, crm: :salesforce)

      assert {:ok, [%{field: "phone", new_value: "555-0100"}]} = result
    end

    test "delegates and returns error" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, _opts ->
        {:error, :generation_failed}
      end)

      result = SocialScribe.AIContentGeneratorApi.generate_crm_suggestions(%{}, [])
      assert {:error, :generation_failed} = result
    end
  end

  describe "generate_chat_response/2 delegation" do
    test "delegates to configured implementation and returns success" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn query, context ->
        assert query == "Tell me about John"
        assert context.crm == :hubspot
        {:ok, "John is a contact in HubSpot."}
      end)

      result =
        SocialScribe.AIContentGeneratorApi.generate_chat_response("Tell me about John", %{
          crm: :hubspot,
          contact: %{name: "John"},
          conversation_history: []
        })

      assert {:ok, "John is a contact in HubSpot."} = result
    end

    test "delegates to configured implementation and returns error" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _query, _context ->
        {:error, :api_timeout}
      end)

      result =
        SocialScribe.AIContentGeneratorApi.generate_chat_response("Hello", %{
          crm: nil,
          contact: nil,
          conversation_history: []
        })

      assert {:error, :api_timeout} = result
    end
  end
end
