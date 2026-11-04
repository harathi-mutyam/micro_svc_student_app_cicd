#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------
# Configuration
# --------------------------------------------------
POLICY_NAME="StudentLokiS3Policy"

# --------------------------------------------------
# Validate bucket variables
# --------------------------------------------------
if [[ -z "${LOKI_CHUNKS_BUCKET:-}" || -z "${LOKI_RULER_BUCKET:-}" ]]; then
    echo "ERROR: Set both bucket environment variables."
    echo "Example:"
    echo 'export LOKI_CHUNKS_BUCKET="your-chunks-bucket"'
    echo 'export LOKI_RULER_BUCKET="your-ruler-bucket"'
    exit 1
fi

# --------------------------------------------------
# Check AWS CLI
# --------------------------------------------------
if ! command -v aws >/dev/null 2>&1; then
    echo "ERROR: AWS CLI is not installed."
    exit 1
fi

# --------------------------------------------------
# Generate IAM policy JSON
# --------------------------------------------------
POLICY_FILE="/tmp/student-loki-s3-policy.json"

cat > "$POLICY_FILE" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": [
        "arn:aws:s3:::${LOKI_CHUNKS_BUCKET}",
        "arn:aws:s3:::${LOKI_RULER_BUCKET}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${LOKI_CHUNKS_BUCKET}/*",
        "arn:aws:s3:::${LOKI_RULER_BUCKET}/*"
      ]
    }
  ]
}
EOF

echo "IAM policy document generated."

# --------------------------------------------------
# Create IAM policy
# --------------------------------------------------
aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://$POLICY_FILE" \
    2>/dev/null || true

# --------------------------------------------------
# Cleanup
# --------------------------------------------------
rm -f "$POLICY_FILE"

echo "Loki S3 IAM policy command completed."
