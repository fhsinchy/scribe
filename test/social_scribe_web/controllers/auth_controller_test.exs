defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase

  import SocialScribe.AccountsFixtures

  describe "Salesforce OAuth callback" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "successful callback creates credential and redirects to settings", %{
      conn: conn,
      user: user
    } do
      auth = %Ueberauth.Auth{
        uid: "sf_user_123",
        provider: :salesforce,
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_access_token",
          refresh_token: "sf_refresh_token",
          expires_at: DateTime.to_unix(DateTime.add(DateTime.utc_now(), 3600, :second)),
          other: %{instance_url: "https://test.salesforce.com"}
        },
        info: %Ueberauth.Auth.Info{
          email: "sf_user@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/salesforce/callback", %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Salesforce account connected"

      # Verify credential was persisted
      credential = SocialScribe.Accounts.get_user_salesforce_credential(user.id)
      assert credential != nil
      assert credential.provider == "salesforce"
      assert credential.uid == "sf_user_123"
      assert credential.token == "sf_access_token"
    end

    @tag capture_log: true
    test "failed callback shows error and redirects to settings", %{conn: conn, user: user} do
      # uid: nil causes a validation error on credential insert
      auth = %Ueberauth.Auth{
        uid: nil,
        provider: :salesforce,
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_access_token",
          refresh_token: "sf_refresh_token",
          expires_at: nil,
          other: %{instance_url: "https://test.salesforce.com"}
        },
        info: %Ueberauth.Auth.Info{
          email: "sf_user@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/salesforce/callback", %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not connect Salesforce"

      # No credential should have been created
      assert SocialScribe.Accounts.get_user_salesforce_credential(user.id) == nil
    end
  end
end
