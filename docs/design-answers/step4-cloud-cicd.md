# Step 4.1 — Moving macOS CI/CD to the Cloud

## Problem

On-premises macOS build machines for Unity iOS/Android builds are overwhelmed.
Too many jobs queue, slowing the release cycle.

## Architecture: AWS EC2 Mac Instances + Self-Hosted GitHub Actions Runners

```
Developers push code
      │
      ▼
GitHub Actions Workflow triggered
      │
      ▼
GitHub Actions Runner Controller (on EKS)
picks up the job and routes to:
      │
      ├── EC2 Mac1 instance (macOS 13, ARM)  ← iOS builds
      │   (self-hosted runner registered)
      └── EC2 Android builder (Linux, x86)   ← Android builds
```

### a) CI/CD Cloud Migration Plan

**Phase 1 — Pilot (Week 1-2):**
- Provision 2x `mac1.metal` EC2 instances (macOS 12/13, 1 year dedicated host)
- Install GitHub Actions runner, Unity Hub, Xcode
- Mirror one existing Jenkins pipeline as a GitHub Actions workflow
- Validate build parity (output checksums match on-prem)

**Phase 2 — Parallel Run (Week 3-4):**
- Route 30% of builds to cloud runners
- Monitor build times, failure rates, cost
- Auto-scale runner count with Actions Runner Controller (ARC) based on queue depth

**Phase 3 — Full Migration (Week 5-6):**
- Route all builds to cloud
- Keep 1 on-prem machine as emergency fallback
- Decommission or repurpose remaining machines

### b) Handling Build Artifacts

- **iOS IPA/dSYM** → upload to **AWS S3** (signed URL for download)
- **Firebase App Distribution** → for QA/beta testing (install link on mobile)
- **TestFlight** → for App Store review builds
- **Version manifest JSON** → S3 public file listing latest builds per branch

```yaml
# GitHub Actions step: upload artifact
- name: Upload IPA to S3
  run: |
    aws s3 cp build/*.ipa s3://dreamgames-builds/${{ github.ref_name }}/${{ github.sha }}/
    echo "Download: https://builds.dreamgames.com/${{ github.ref_name }}/${{ github.sha }}/app.ipa"
```

### c) Licensing Challenges

| Challenge | Solution |
|-----------|---------|
| Xcode requires Apple Developer subscription | One team Apple Developer account, credentials in AWS Secrets Manager |
| Unity license is per-machine (floating) | Unity License Server on EC2 (supports floating seats); or Unity Cloud Build |
| macOS EULA: Apple limits running macOS to Apple hardware only | Use EC2 Mac `mac1.metal` / `mac2.metal` — runs on genuine Apple Mac Mini/Mac Pro in AWS DCs. EULA compliant. |
| Code signing certificates | Store p12 + provisioning profiles in AWS Secrets Manager; inject via fastlane match |

## Reviewer Defense

> "EC2 Mac instances are the only AWS-native, Apple-EULA-compliant option for running
> macOS at scale. The minimum commitment is a 24-hour dedicated host, but with Actions
> Runner Controller we can dynamically scale runners on those hosts. For Unity licensing,
> Unity's floating license server means one license covers all runners, not one per machine.
> Fastlane Match handles code signing centrally via a Git repo with encrypted certs —
> no engineer needs certificates locally."
