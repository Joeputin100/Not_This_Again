# Android — one-time setup

This directory is the future home of the **custom Android build template** (manifest overrides for edge-to-edge + predictive back gesture). For now, it's the documentation home for the one-time signing + CI auth setup.

## Signing keystore

The Android **release keystore** is stored in two places:
1. **Google Secret Manager** (`android-release-keystore` in GCP project `static-webbing-461904-c4`) — for CI access
2. **Proton Pass** (user's personal vault) — for human recovery

**Never commit the keystore file to git.** It's covered by `.gitignore` at the repo root.

### Keystore properties

- Format: PKCS#12 (`.p12`)
- Alias: `not_this_again_release`
- Algorithm: RSA 4096
- Validity: 10000 days from 2026-05-11

### Keystore password

Stored separately in Secret Manager as `android-keystore-password`.

### Regenerating (DO NOT do casually — see warnings)

The upload key is permanent for the app's Play Store identity. **Do not regenerate** after first publish unless you have enrolled in Play App Signing (Google holds the real signing key, you can rotate the upload key).

If you must regenerate before first publish:

```bash
rm -f my-release-key.p12
keytool -genkeypair \
  -alias not_this_again_release \
  -keyalg RSA -keysize 4096 \
  -validity 10000 \
  -keystore my-release-key.p12 \
  -storetype PKCS12

# Upload new version to Secret Manager
gcloud secrets versions add android-release-keystore \
  --data-file=my-release-key.p12

# Disable old version (don't destroy — disable is reversible)
gcloud secrets versions disable <OLD_VERSION> --secret=android-release-keystore

# Update password if it changed
read -s -p "New keystore password: " KS_PW; echo
printf %s "$KS_PW" | gcloud secrets versions add android-keystore-password --data-file=-
unset KS_PW

# Back up to Proton Pass before deleting local
# (attach my-release-key.p12 to a vault entry, then:)
rm my-release-key.p12
```

## Workload Identity Federation (GH Actions → GCP)

The release workflow authenticates to GCP using GitHub's OIDC token (no long-lived service-account JSON keys). One-time setup:

```bash
export PROJECT=static-webbing-461904-c4
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
export GH_REPO="<owner>/<repo>"   # e.g. joeputin100/Not_This_Again

# 1. Create workload identity pool
gcloud iam workload-identity-pools create github \
  --location=global --display-name="GitHub Actions"

# 2. Create OIDC provider for GitHub
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global --workload-identity-pool=github \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# 3. Create service account
gcloud iam service-accounts create gh-actions-keystore \
  --display-name="GH Actions keystore reader"

# 4. Grant minimal Secret Manager access (only the two secrets we need)
gcloud secrets add-iam-policy-binding android-release-keystore \
  --member="serviceAccount:gh-actions-keystore@$PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding android-keystore-password \
  --member="serviceAccount:gh-actions-keystore@$PROJECT.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 5. Bind workload identity to service account, restricted to this GH repo
gcloud iam service-accounts add-iam-policy-binding \
  gh-actions-keystore@$PROJECT.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository/$GH_REPO"

# 6. Print the values to add as GitHub Secrets
echo
echo "Add to GitHub repo secrets:"
echo "  GCP_WIF_PROVIDER  = projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github-provider"
echo "  GCP_SERVICE_ACCOUNT = gh-actions-keystore@$PROJECT.iam.gserviceaccount.com"
```

Then in the GitHub repo settings → Secrets and variables → Actions, add the two pointer values printed in step 6. **Note: these are not "secrets" in the cryptographic sense — they're just resource identifiers — but GitHub's UI calls them secrets.**

## Why no service-account JSON key?

A service-account key stored in GitHub Secrets is a long-lived credential that lives in your GitHub org forever, can be exfiltrated by malicious workflow code, and has no expiry. WIF replaces it with short-lived tokens scoped to a specific GitHub repository — significantly smaller attack surface.

## CI debug builds — no GCP auth needed

The debug workflow (`android-debug.yml`) doesn't sign with the release keystore; it uses Godot's auto-generated debug keystore. So debug builds work without any of the above being set up.

The release workflow (`android-release.yml`) is the one that needs WIF + Secret Manager access.
