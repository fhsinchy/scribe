# Setting up Salesforce OAuth

Users connect their Salesforce account from the Settings page. To make that work, you need to create an External Client App in Salesforce. Here's how.

## What you need

- A Salesforce account. If you don't have one, grab a free Developer Edition at [developer.salesforce.com/signup](https://developer.salesforce.com/signup)
- Admin access to Salesforce Setup

## Open the App Manager

1. Log in to your Salesforce org
2. Click the gear icon (top right) and pick "Setup"
3. In the sidebar or Quick Find search, search for "App Manager"
4. Click "App Manager"

## Create the app

1. Click "New External Client App" -- not "New Lightning App" (that's for building Salesforce UI apps, which isn't what we want)
2. Fill in:
   - External Client App Name: "Social Scribe" (or whatever you like)
   - Contact Email: your email
3. Click "Save"

## Configure OAuth

1. You should be on the app's detail page after saving
2. Find the OAuth Settings section. You may need to click "Configure" or "Edit" under API/OAuth settings
3. Turn on OAuth 2.0
4. Set the Callback URL:
   - Local dev: `http://localhost:4000/auth/salesforce/callback`
   - Production: `https://yourdomain.com/auth/salesforce/callback`
5. Under Selected OAuth Scopes, add these two:
   - "Full access (full)"
   - "Perform requests at any time (refresh_token, offline_access)"
6. PKCE (Proof Key for Code Exchange) should be on by default for External Client Apps. Leave it enabled -- the app already handles it
7. Click "Save"

## Grab the Consumer Key and Secret

1. Go back to the app's detail page
2. Find the Consumer Key and Secret section. You might need to click "Manage Consumer Details" or something similar
3. Salesforce will probably ask you to verify your identity (email code)
4. Copy the Consumer Key (this is your Client ID) and Consumer Secret (this is your Client Secret)

Heads up: new apps can take up to 10 minutes to propagate across Salesforce's servers. If you try to connect right away and get an error, wait a bit.

## Add to your .env

```bash
export SALESFORCE_CLIENT_ID="your-consumer-key"
export SALESFORCE_CLIENT_SECRET="your-consumer-secret"
export SALESFORCE_REDIRECT_URI="http://localhost:4000/auth/salesforce/callback"
```

## Test it

```bash
source .env && mix phx.server
```

1. Log in and go to `http://localhost:4000/dashboard/settings`
2. Scroll to "Connected Salesforce Accounts"
3. Click "Connect Salesforce"
4. Salesforce's login page opens -- sign in and authorize the app
5. You get redirected back to Settings with "Salesforce account connected successfully!"
6. Your account shows up in the list with its UID and email

## When things go wrong

### missing required code challenge

The app isn't sending PKCE parameters. Make sure you have the latest Salesforce strategy code -- the version with `code_challenge` and `code_verifier` support.

### invalid_client_id

Copy-paste issue, most likely. Check that `SALESFORCE_CLIENT_ID` in your `.env` matches the Consumer Key in Salesforce Setup. Character for character.

New apps can also take up to 10 minutes to propagate. And make sure you re-sourced your `.env` (`source .env`).

### redirect_uri_mismatch

The callback URL in the Salesforce app has to match exactly: `http://localhost:4000/auth/salesforce/callback`. Watch for trailing slashes or http/https mismatches.

### invalid_grant or expired authorization code

Auth codes expire quickly. If you sat on the consent screen too long, just try the flow again.

### code_verifier does not match code_challenge

The session got lost between the authorize request and the callback. This happens if cookies are disabled or you switched browsers mid-flow.

## Good to know

- Salesforce returns an `instance_url` in the token response (something like `https://yourorg.my.salesforce.com`). The app stores it and uses it for all Salesforce API calls. Each org has a different one
- When you refresh a token, Salesforce only gives you a new `access_token`. The original `refresh_token` stays the same
- Access tokens expire after about 2 hours. The app has a background job (`SalesforceTokenRefresher`) that refreshes them before they expire
- Consumer Key can be public. Keep the Consumer Secret private
- For sandbox environments, you'd need to swap `https://login.salesforce.com` for `https://test.salesforce.com` in the OAuth config
