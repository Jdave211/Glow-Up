# GlowUp App Review Reply Draft

Submission ID: `c8cc6bbc-d69c-4c86-b240-4abf79637239`

## 1. Guideline 2.1 / 5.1.1 / 5.1.2 - Face Data + Third-Party AI

Use the following response in App Store Connect after you update the live privacy policy:

> We updated the app to add an explicit permission prompt before any face-photo analysis or AI chat data is sent for third-party AI processing.
>
> GlowUp collects only the user-selected onboarding and progress-check-in photos needed for analysis: front face, left-side face, right-side face, and optional smile/teeth photo. From those photos, GlowUp derives skin-analysis signals including detected skin type/tone, hydration score, oiliness score, texture score, detected concerns, redness areas, pore visibility, and related recommendation tags used to build the personalized routine.
>
> GlowUp uses this face data only to:
> 1. generate the user's personalized skin analysis,
> 2. create and refresh the user's routine and recommendations,
> 3. compare optional photo check-ins over time,
> 4. show private progress insights inside the user's own account.
>
> Face data is not shared with other users. It is transmitted to GlowUp's backend and stored in private Supabase storage/database infrastructure. GlowUp also sends the relevant request data to the OpenAI API to generate the analysis/recommendation output. OpenAI API data is processed via the API; per OpenAI's API policy, API content is not used to train OpenAI models by default and may be retained for up to 30 days for abuse and misuse monitoring.
>
> Retention:
> - If Photo Check-ins is enabled, raw uploaded face photos and derived face-analysis payloads are retained for up to 90 days to support progress tracking.
> - If Photo Check-ins is disabled, raw uploaded onboarding photos are deleted after analysis and only the non-photo account/routine data needed to operate the app remains.
> - Expired face-photo references and retained face-analysis payloads are redacted automatically by the backend after the retention window.
>
> We also added in-app disclosures naming the data sent, the parties receiving it, and the retention behavior before the user can proceed.

## 2. Privacy Policy Text To Add

Add these section titles and exact text to the live privacy policy:

### Face Data and Photo Analysis

> If you choose to use GlowUp's photo analysis or photo check-in features, we collect the photos you upload for analysis, including front-face, left-side, right-side, and optional smile/teeth photos. From those photos, we derive face and skin-analysis data such as detected skin type, detected skin tone, hydration score, oiliness score, texture score, detected concerns, redness areas, pore visibility, and related recommendation tags. We use this information only to generate your personalized analysis, recommendations, routine updates, and optional progress tracking inside your account.

### Sharing With Service Providers

> We do not share face data with other users. We share uploaded photos and related analysis request data only with service providers needed to operate the feature: Supabase, which stores private application data and private photo files for GlowUp, and OpenAI, which processes AI analysis and recommendation requests for the GlowUp service. OpenAI API content is not used to train OpenAI models by default and may be retained for up to 30 days for abuse and misuse monitoring.

### Retention and Deletion

> If Photo Check-ins is enabled, GlowUp retains uploaded face photos and derived face-analysis payloads for up to 90 days so the user can compare progress over time. If Photo Check-ins is disabled, GlowUp deletes raw uploaded onboarding photos after analysis completes. Face-photo references and retained face-analysis payloads that exceed the retention window are automatically redacted. Users may also request deletion by deleting their account, which removes associated account data from GlowUp's backend.

### User Permission

> GlowUp asks for the user's permission before sending face photos, analysis inputs, or chat data for third-party AI processing.

## 3. Guideline 2.1 - No Content After Skin Analysis

Suggested response:

> We fixed the post-analysis flow. The app now shows a dedicated analysis summary screen immediately after skin analysis completes, before entering the main app or purchase flow, so content is visible reliably during first-run review. We also verified the target remains configured as iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), but we hardened the compatibility-mode flow because App Review may still test the iPhone build on iPad.

## 4. Guideline 3.1.2 - Subscription Metadata

What to change in App Store Connect:

- Add the Terms of Use URL to the App Description or the EULA field:
  `https://boiled-education-5d3.notion.site/GlowUp-Terms-of-Service-a17b8e90751743dba5a33e2a03dd4b64?source=copy_link`
- Keep the Privacy Policy URL in the Privacy Policy field:
  `https://boiled-education-5d3.notion.site/GlowUp-Privacy-Policy-867796a49e504c3d839ce15de6ade6f3?source=copy_link`

Suggested metadata sentence:

> Terms of Use: https://boiled-education-5d3.notion.site/GlowUp-Terms-of-Service-a17b8e90751743dba5a33e2a03dd4b64?source=copy_link

## 5. Guideline 1.2 - User-Generated Content

If GlowUp does not expose user content to other users, reply with:

> GlowUp does not include a user-to-user social feed, public posting surface, or user-generated content visible to other users. Chat conversations are private one-to-one interactions between the individual user and the app and are not published to a community feed. We have added this clarification to the App Review Information section. If you would like us to treat any specific feature as user-generated content, please let us know which screen triggered the concern.

## 6. App Review Information Note

Add this note to App Review Information:

> GlowUp is an iPhone-only app. App Review may still test it in iPhone compatibility mode on iPad, so we updated the post-analysis flow to show a dedicated summary screen immediately after analysis. The app includes new permission prompts before sending chat data or face-photo analysis data to third-party AI processing.
