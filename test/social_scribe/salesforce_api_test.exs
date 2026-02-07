defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "apply_updates/3" do
    test "returns :no_updates with empty list" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003XXXXXXXXXXXXXXX", [])
    end

    test "filters only updates with apply: false" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003XXXXXXXXXXXXXXX", updates)
    end

    test "mixed apply values - only false returns :no_updates" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false},
        %{field: "city", new_value: "Denver", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003XXXXXXXXXXXXXXX", updates)
    end
  end

  describe "search_contacts/2" do
    test "requires a valid credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
      assert credential.instance_url == "https://test.salesforce.com"
    end
  end

  describe "get_contact/2" do
    test "requires a valid credential and contact_id" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "update_contact/3" do
    test "requires a valid credential, contact_id, and updates map" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "SalesforceApiBehaviour delegation" do
    setup do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      %{credential: credential}
    end

    test "search_contacts delegates to implementation", %{credential: credential} do
      expected = [%{id: "003ABC", firstname: "Test", lastname: "User"}]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.search_contacts(credential, "test query")
    end

    test "get_contact delegates to implementation", %{credential: credential} do
      expected = %{id: "003ABC", firstname: "John", lastname: "Doe"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "003ABC"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.get_contact(credential, "003ABC")
    end

    test "update_contact delegates to implementation", %{credential: credential} do
      updates = %{"Phone" => "555-1234", "Department" => "New Corp"}
      expected = %{id: "003ABC", phone: "555-1234", company: "New Corp"}

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, contact_id, upd ->
        assert contact_id == "003ABC"
        assert upd == updates
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.update_contact(
                 credential,
                 "003ABC",
                 updates
               )
    end

    test "apply_updates delegates to implementation", %{credential: credential} do
      updates_list = [
        %{field: "phone", new_value: "555-1234", apply: true},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:apply_updates, fn _cred, contact_id, list ->
        assert contact_id == "003ABC"
        assert list == updates_list
        {:ok, %{id: "003ABC"}}
      end)

      assert {:ok, _} =
               SocialScribe.SalesforceApiBehaviour.apply_updates(
                 credential,
                 "003ABC",
                 updates_list
               )
    end
  end
end
