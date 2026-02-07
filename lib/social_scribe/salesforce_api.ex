defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @contact_fields ~w(FirstName LastName Email Phone MobilePhone Title Department MailingStreet MailingCity MailingState MailingPostalCode MailingCountry OtherPhone)

  defp client(%UserCredential{} = credential) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, credential.instance_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{credential.token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using SOSL.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      sanitized = sanitize_sosl(query)
      fields = Enum.join(@contact_fields, ",")

      url =
        "/services/data/v59.0/search/?q=FIND+%7B#{URI.encode(sanitized)}%7D+IN+ALL+FIELDS+RETURNING+Contact(Id,#{fields}+LIMIT+10)"

      case Tesla.get(client(cred), url) do
        {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => records}}} ->
          contacts = Enum.map(records, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by ID.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      url = "/services/data/v59.0/sobjects/Contact/#{contact_id}"

      case Tesla.get(client(cred), url) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body)}

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of Salesforce field names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      url = "/services/data/v59.0/sobjects/Contact/#{contact_id}"

      case Tesla.patch(client(cred), url, updates) do
        {:ok, %Tesla.Env{status: 204}} ->
          # Salesforce returns 204 No Content on success, re-fetch the contact
          get_contact_direct(cred, contact_id)

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, field_to_salesforce(update.field), update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  # Direct get without token refresh wrapper (used after successful update)
  defp get_contact_direct(%UserCredential{} = cred, contact_id) do
    url = "/services/data/v59.0/sobjects/Contact/#{contact_id}"

    case Tesla.get(client(cred), url) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, format_contact(body)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(contact) when is_map(contact) do
    %{
      id: contact["Id"],
      firstname: contact["FirstName"],
      lastname: contact["LastName"],
      email: contact["Email"],
      phone: contact["Phone"],
      mobilephone: contact["MobilePhone"],
      jobtitle: contact["Title"],
      company: contact["Department"],
      address: contact["MailingStreet"],
      city: contact["MailingCity"],
      state: contact["MailingState"],
      zip: contact["MailingPostalCode"],
      country: contact["MailingCountry"],
      display_name: format_display_name(contact)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(contact) do
    firstname = contact["FirstName"] || ""
    lastname = contact["LastName"] || ""
    email = contact["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Map internal field names to Salesforce API field names
  defp field_to_salesforce("firstname"), do: "FirstName"
  defp field_to_salesforce("lastname"), do: "LastName"
  defp field_to_salesforce("email"), do: "Email"
  defp field_to_salesforce("phone"), do: "Phone"
  defp field_to_salesforce("mobilephone"), do: "MobilePhone"
  defp field_to_salesforce("jobtitle"), do: "Title"
  defp field_to_salesforce("company"), do: "Department"
  defp field_to_salesforce("address"), do: "MailingStreet"
  defp field_to_salesforce("city"), do: "MailingCity"
  defp field_to_salesforce("state"), do: "MailingState"
  defp field_to_salesforce("zip"), do: "MailingPostalCode"
  defp field_to_salesforce("country"), do: "MailingCountry"
  defp field_to_salesforce(field), do: field

  # Sanitize SOSL special characters
  defp sanitize_sosl(query) do
    query
    |> String.replace(~r/[?&|!{}\[\]()\^~*:\\"'+\-]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Wrapper that handles token refresh on auth errors
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, status, body}} when status in [401, 400] ->
          if is_token_error?(body) do
            Logger.info("Salesforce token expired, refreshing and retrying...")
            retry_with_fresh_token(credential, api_call)
          else
            Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}
          end

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(body) when is_list(body) do
    Enum.any?(body, fn
      %{"errorCode" => code} -> code in ["INVALID_SESSION_ID", "INVALID_AUTH_HEADER"]
      _ -> false
    end)
  end

  defp is_token_error?(_), do: false
end
