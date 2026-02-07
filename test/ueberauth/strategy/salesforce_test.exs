defmodule Ueberauth.Strategy.SalesforceTest do
  use ExUnit.Case, async: true

  alias Ueberauth.Strategy.Salesforce

  describe "uid/1" do
    test "extracts user_id from connection private data" do
      conn = %Plug.Conn{
        private: %{
          salesforce_user: %{"user_id" => "005ABC123", "email" => "user@example.com"},
          ueberauth_request_options: %{options: [uid_field: :user_id]}
        }
      }

      assert Salesforce.uid(conn) == "005ABC123"
    end
  end

  describe "info/1" do
    test "extracts email and name from user data" do
      conn = %Plug.Conn{
        private: %{
          salesforce_user: %{
            "email" => "jane@example.com",
            "name" => "Jane Smith"
          }
        }
      }

      info = Salesforce.info(conn)
      assert info.email == "jane@example.com"
      assert info.name == "Jane Smith"
    end

    test "handles missing fields gracefully" do
      conn = %Plug.Conn{
        private: %{
          salesforce_user: %{}
        }
      }

      info = Salesforce.info(conn)
      assert info.email == nil
      assert info.name == nil
    end
  end

  describe "credentials/1" do
    test "extracts token data and instance_url from connection" do
      token = %OAuth2.AccessToken{
        access_token: "sf_token_abc",
        refresh_token: "sf_refresh_xyz",
        expires_at: 1_700_000_000,
        token_type: "Bearer",
        other_params: %{
          "scope" => "full refresh_token",
          "instance_url" => "https://myorg.salesforce.com"
        }
      }

      conn = %Plug.Conn{
        private: %{salesforce_token: token}
      }

      creds = Salesforce.credentials(conn)
      assert creds.token == "sf_token_abc"
      assert creds.refresh_token == "sf_refresh_xyz"
      assert creds.expires == true
      assert creds.expires_at == 1_700_000_000
      assert creds.token_type == "Bearer"
      assert creds.other.instance_url == "https://myorg.salesforce.com"
      assert "full" in creds.scopes
      assert "refresh_token" in creds.scopes
    end

    test "handles nil scope in token" do
      token = %OAuth2.AccessToken{
        access_token: "tok",
        refresh_token: "ref",
        expires_at: nil,
        token_type: "Bearer",
        other_params: %{}
      }

      conn = %Plug.Conn{private: %{salesforce_token: token}}

      creds = Salesforce.credentials(conn)
      assert creds.scopes == [""]
    end
  end

  describe "extra/1" do
    test "returns raw token and user data" do
      token = %OAuth2.AccessToken{
        access_token: "tok",
        refresh_token: "ref",
        expires_at: nil,
        token_type: "Bearer",
        other_params: %{}
      }

      user = %{"user_id" => "005", "email" => "user@test.com"}

      conn = %Plug.Conn{
        private: %{
          salesforce_token: token,
          salesforce_user: user
        }
      }

      extra = Salesforce.extra(conn)
      assert extra.raw_info.token == token
      assert extra.raw_info.user == user
    end
  end

  describe "handle_cleanup!/1" do
    test "clears salesforce private data from connection" do
      conn =
        %Plug.Conn{}
        |> Plug.Conn.put_private(:salesforce_token, %{some: "token"})
        |> Plug.Conn.put_private(:salesforce_user, %{some: "user"})

      cleaned = Salesforce.handle_cleanup!(conn)
      assert cleaned.private.salesforce_token == nil
      assert cleaned.private.salesforce_user == nil
    end
  end

  describe "handle_callback!/1" do
    test "sets error when no code parameter is present" do
      conn = %Plug.Conn{
        params: %{},
        private: %{
          ueberauth_request_options: %{
            options: [],
            callback_methods: ["GET"],
            callback_params: nil,
            callback_path: "/auth/salesforce/callback",
            callback_port: nil,
            callback_scheme: nil,
            callback_url: "http://localhost:4000/auth/salesforce/callback"
          }
        }
      }

      result = Salesforce.handle_callback!(conn)
      assert %Plug.Conn{} = result

      failure = result.assigns[:ueberauth_failure]
      assert failure != nil
      assert length(failure.errors) > 0
      assert hd(failure.errors).message_key == "missing_code"
    end
  end
end
