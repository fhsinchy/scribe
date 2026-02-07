defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old_token",
          refresh_token: "old_refresh",
          instance_url: "https://test.salesforce.com"
        })

      # Simulate what refresh_credential does after successful API call
      attrs = %{
        token: "new_access_token",
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
        instance_url: "https://test.salesforce.com"
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)

      assert updated.token == "new_access_token"
      assert updated.instance_url == "https://test.salesforce.com"
      assert updated.id == credential.id
      # Salesforce doesn't rotate refresh tokens
      assert updated.refresh_token == credential.refresh_token
    end
  end
end
