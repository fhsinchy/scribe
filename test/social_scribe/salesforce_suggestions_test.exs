defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceSuggestions

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Department",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XXXXXXXXXXXXXXX",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XXXXXXXXXXXXXXX",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "003XXXXXXXXXXXXXXX", email: "test@example.com"}

      result = SalesforceSuggestions.merge_with_contact([], contact)

      assert result == []
    end

    test "sets apply to true and updates current_value from contact" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-9999",
          context: "New phone",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003ABC", phone: "555-0000"}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(result) == 1
      suggestion = hd(result)
      assert suggestion.apply == true
      assert suggestion.current_value == "555-0000"
      assert suggestion.has_change == true
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003XXXXXXXXXXXXXXX", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end
  end

  describe "generate_suggestions/3" do
    test "fetches contact and AI suggestions, merges and filters" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      mock_contact = %{
        id: "003ABC",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: nil,
        mobilephone: nil,
        jobtitle: nil,
        company: "Acme Corp",
        address: nil,
        city: nil,
        state: nil,
        zip: nil,
        country: nil,
        display_name: "John Doe"
      }

      mock_ai_suggestions = [
        %{field: "phone", value: "555-1234", context: "Mentioned phone number"},
        %{field: "company", value: "Acme Corp", context: "Works at Acme"}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "003ABC"
        {:ok, mock_contact}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, opts ->
        assert opts == [crm: :salesforce]
        {:ok, mock_ai_suggestions}
      end)

      meeting = %{id: "meeting-1", title: "Test Meeting"}

      assert {:ok, %{contact: contact, suggestions: suggestions}} =
               SalesforceSuggestions.generate_suggestions(credential, "003ABC", meeting)

      assert contact.id == "003ABC"
      # Only phone should appear (company matches existing value)
      assert length(suggestions) == 1
      assert hd(suggestions).field == "phone"
      assert hd(suggestions).new_value == "555-1234"
      assert hd(suggestions).current_value == nil
      assert hd(suggestions).apply == true
    end

    test "returns error when get_contact fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, _contact_id ->
        {:error, :not_found}
      end)

      meeting = %{id: "meeting-1", title: "Test Meeting"}

      assert {:error, :not_found} =
               SalesforceSuggestions.generate_suggestions(credential, "003ABC", meeting)
    end

    test "returns error when AI suggestion generation fails" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, _contact_id ->
        {:ok, %{id: "003ABC", phone: nil, email: nil}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, _opts ->
        {:error, :ai_unavailable}
      end)

      meeting = %{id: "meeting-1", title: "Test Meeting"}

      assert {:error, :ai_unavailable} =
               SalesforceSuggestions.generate_suggestions(credential, "003ABC", meeting)
    end
  end

  describe "generate_suggestions_from_meeting/1" do
    test "returns formatted suggestions from AI" do
      mock_ai_suggestions = [
        %{field: "phone", value: "555-1234", context: "Mentioned phone", timestamp: "00:15"},
        %{field: "jobtitle", value: "CTO", context: "Title mentioned", timestamp: "01:30"}
      ]

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, opts ->
        assert opts == [crm: :salesforce]
        {:ok, mock_ai_suggestions}
      end)

      meeting = %{id: "meeting-1", title: "Test Meeting"}

      assert {:ok, suggestions} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)

      assert length(suggestions) == 2

      phone_suggestion = Enum.find(suggestions, &(&1.field == "phone"))
      assert phone_suggestion.new_value == "555-1234"
      assert phone_suggestion.label == "Phone"
      assert phone_suggestion.current_value == nil
      assert phone_suggestion.apply == true
      assert phone_suggestion.has_change == true
      assert phone_suggestion.timestamp == "00:15"

      title_suggestion = Enum.find(suggestions, &(&1.field == "jobtitle"))
      assert title_suggestion.new_value == "CTO"
      assert title_suggestion.label == "Title"
    end

    test "returns error when AI fails" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, _opts ->
        {:error, :ai_unavailable}
      end)

      meeting = %{id: "meeting-1", title: "Test Meeting"}

      assert {:error, :ai_unavailable} =
               SalesforceSuggestions.generate_suggestions_from_meeting(meeting)
    end

    test "returns empty suggestions list when AI returns none" do
      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_crm_suggestions, fn _meeting, _opts ->
        {:ok, []}
      end)

      meeting = %{id: "meeting-1", title: "Test Meeting"}

      assert {:ok, []} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)
    end
  end
end
