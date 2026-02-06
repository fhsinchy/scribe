# Setting up Google OAuth

You need a Google OAuth client so users can sign in and the app can read their Google Calendar. Here's how to set one up.

## What you need

- A Google account
- Access to [Google Cloud Console](https://console.cloud.google.com)

## Create a Google Cloud project

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Click the project dropdown at the top of the page (next to the "Google Cloud" logo)
3. Click "New Project"
4. Name it something like "Social Scribe"
5. Click "Create"
6. Make sure the new project is selected in the project dropdown

## Set up the consent screen

This is the screen users see when they sign in with Google. Google won't let you create credentials without configuring it first.

1. In the left sidebar, go to "APIs & Services > OAuth consent screen". Google has been shuffling this UI around -- you might find it under "Google Auth Platform > Branding" and "Google Auth Platform > Audience" instead
2. Pick "External" as the user type, click "Create"
3. On the Branding page, fill in:
   - App name: "Social Scribe" (or whatever you want)
   - User support email: pick yours from the dropdown
   - Scroll down to Developer contact information, enter your email there too
4. Click "Save"
5. Skip the Scopes step entirely (just click Save and Continue). The app already requests the scopes it needs at login time through `config/config.exs`
6. Go to the Audience page (or "Test users" step):
   - Click "+ Add users"
   - Enter the Google email(s) you'll test with
   - Click "Save"

While the app is in "Testing" mode, only users you list here can sign in. Everyone else gets a 403.

## Turn on the Google Calendar API

1. In the left sidebar, go to "APIs & Services > Library"
2. Search for "Google Calendar API"
3. Click it, then click "Enable"

Without this, calendar sync won't work. The sign-in itself will still function fine.

## Create the OAuth credentials

1. In the left sidebar, go to "APIs & Services > Credentials" (or "Google Auth Platform > Clients")
2. Click "+ Create Credentials" (or "+ Create Client")
3. Pick "OAuth client ID"
4. Application type: "Web application"
5. Give it a name (doesn't matter much, "Web client 1" is fine)
6. Under "Authorized redirect URIs", click "+ Add URI" and enter:
   - Local dev: `http://localhost:4000/auth/google/callback`
   - Production: `https://yourdomain.com/auth/google/callback`
7. Click "Create"
8. Copy the Client ID and Client Secret from the dialog that pops up

## Add to your .env

```bash
export GOOGLE_CLIENT_ID="your-client-id.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="GOCSPX-your-client-secret"
export GOOGLE_REDIRECT_URI="http://localhost:4000/auth/google/callback"
```

## Test it

```bash
source .env && mix phx.server
```

Go to `http://localhost:4000`, click "Sign in with Google", sign in with an account you added as a test user. You should land on the dashboard.

## When things go wrong

### Error 401: invalid_client

This one is almost always a copy-paste problem. Check that `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in your `.env` match exactly what's in the Google Cloud Console. No extra spaces, no missing characters.

Also:
- Did you re-source your `.env`? (`source .env`)
- New OAuth clients can take 5-15 minutes to propagate on Google's end. Just wait a bit
- Try an incognito window to rule out stale cookies

### Error 403: access_denied

Your Google account isn't listed as a test user. Go to the Audience page in the consent screen settings and add it.

### redirect_uri_mismatch

The redirect URI in Google Console has to match exactly: `http://localhost:4000/auth/google/callback`. Watch out for trailing slashes, and make sure it's `http` not `https` for local dev. The `GOOGLE_REDIRECT_URI` in your `.env` needs to match too.

## Good to know

- To let anyone sign in (not just test users), click "Publish app" on the Audience page. Google may require verification for certain scopes
- The scopes the app requests are in `config/config.exs` under the Ueberauth Google provider: `email profile https://www.googleapis.com/auth/calendar.readonly`
- The Client ID can be public. Keep the Client Secret private
