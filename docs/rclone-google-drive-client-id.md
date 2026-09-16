# Making your own rclone client_id for Google Drive

When you use rclone with Google Drive in its default configuration you are using rclone's shared client_id. This shared client_id is being retired and will stop working during 2026. To avoid interruption you must create and use your own client_id — this is now required, not merely recommended. New remotes created with `rclone config` will warn you if you leave the client_id blank.

Using your own client_id has other benefits too: Google sets a global rate limit on queries per second *per client_id*. If you run multiple services, give each its own client_id. The default Google quota is 10 transactions/second, so staying under that avoids rclone hitting rate limits and slowing down.

Google reorganized this part of the Cloud Console in 2024: what used to be the single "OAuth consent screen" page is now **Google Auth Platform**, a top-level item in the left-hand menu with its own set of tabs (**Overview**, **Branding**, **Audience**, **Clients**, **Data Access**). The steps below reflect that current layout.

Here is how to create your own Google Drive client ID for rclone:

1. Log into the [Google Cloud Console](https://console.cloud.google.com/) with any Google account — it doesn't need to be the same account as the Google Drive you want to access.
2. Select a project, or create a new one, from the project picker at the top of the page.
3. Go to **APIs & Services → Library**, search for "Drive", and enable the **Google Drive API**.
4. In the left-hand menu, click **Google Auth Platform**. If this project hasn't configured it before, you'll land on the **Overview** tab with a **"Get started"** button — click it and fill in the wizard:
   - **App Information**: an "App name" (`rclone` is fine) and a "User support email" (your own address is fine).
   - **Audience**: choose **External**. *(If you're on a Google Workspace/GSuite account you can instead choose **Internal**, but that restricts use to accounts inside your organization.)*
   - **Contact Information**: your own email, for Google's project notifications.
   - Agree to the Google API Services User Data Policy and click **Create**.
5. Click the **Data Access** tab (this replaced the old "scopes" step). Click **"Add or remove scopes"**, and either tick or manually add these three scopes:
   - `https://www.googleapis.com/auth/docs`
   - `https://www.googleapis.com/auth/drive` — needed for rclone to create, edit, and delete files.
   - `https://www.googleapis.com/auth/drive.metadata.readonly`

   To add them manually, scroll down to the "Manually add scopes" box, paste all three comma-separated, click **Add**, then **Update**. Confirm all three now appear on the Data Access page, then click **Save** at the bottom.
6. Click the **Audience** tab. Scroll to "Test users", click **"+ Add users"**, add your own Google account, and **Save**. (Apps in "Testing" status are capped at 100 test users, and grants expire weekly — see the note on publishing below.)
7. Click the **Clients** tab (this is now the correct home for OAuth client IDs — it's no longer under a generic "Credentials" page). Click **"+ Create Client"**, set application type to **Desktop app**, leave the default name, and click **Create**.
8. The console shows a **Client ID** and **Client secret**. Copy both immediately — the secret is not retrievable again later. *(If you selected External audience, continue to step 9; if Internal, skip to step 10 — your destination Drive must still belong to the same Workspace.)*
9. Go back to the **Audience** tab and click **"Publish App"**, then confirm.
   - If **"Publish App"** is greyed out, Google now requires a homepage and privacy policy link before it will let you publish, even for a personal single-user app. Go to the **Branding** tab, fill in **"Homepage URL"** and **"Privacy Policy link"** under "App Domain" (a free GitHub Pages site works fine for these if you don't own a domain), add that domain under **"Authorized Domains"**, and **Save**. Return to **Audience** — "Publish App" should now be clickable.
10. Give rclone the client ID and client secret you copied in step 8 (via `rclone config`).
11. Run the web-based authorization flow from within `rclone config` — answer "Y" when it asks "Token already configured - replace it?".

## On verification

Google's UI will nudge you to "submit your app for verification," which can take weeks. In practice you don't need to for personal use — Google [exempts several app categories](https://support.google.com/cloud/answer/13464323) from mandatory verification:

- **Personal use apps** (fewer than 100 users): you and your users just click through an "unverified app" warning screen during sign-in. Verification is only required past 100 users.
- **Development/Testing apps**: also exempt, but capped at 100 users and still show the warning screen.

For typical personal rclone use: leave the app unverified, accept the warning screen once during the `rclone config` auth flow, and **publish** the app (rather than leaving it in "Testing") — publishing avoids the weekly token-expiry that Testing-status apps are stuck with.

## Sources

- [rclone.org Google Drive docs](https://rclone.org/drive/)
- [Get started with the Google Auth Platform](https://support.google.com/cloud/answer/15544987?hl=en)
- [Manage OAuth Clients](https://support.google.com/cloud/answer/15549257?hl=en)
- [Manage App Audience](https://support.google.com/cloud/answer/15549945?hl=en)
- [Manage OAuth App Branding](https://support.google.com/cloud/answer/15549049?hl=en)
- [Configure the OAuth consent screen and choose scopes](https://developers.google.com/workspace/guides/configure-oauth-consent)
- [App verification exemptions](https://support.google.com/cloud/answer/13464323)
