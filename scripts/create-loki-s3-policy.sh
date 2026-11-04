#!/usr/bin/env bash
set -e

# Validate arguments
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <CHUNKS_BUCKET> <RULER_BUCKET>"
  exit 1
fi

CHUNKS_BUCKET="$1"
RULER_BUCKET="$2"
POLICY_NAME="StudentLokiS3Policy"

echo "Creating IAM policy for:"
echo " - Chunks: $CHUNKS_BUCKET"
echo " - Ruler:  $RULER_BUCKET"

# Generate temporary policy document
cat <<EOF > /tmp/loki-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::${CHUNKS_BUCKET}",
        "arn:aws:s3:::${RULER_BUCKET}"
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
        "arn:aws:s3:::${CHUNKS_BUCKET}/*",
        "arn:aws:s3:::${RULER_BUCKET}/*"
      ]
    }
  ]
}
EOF

# Create policy (or skip if already created)
aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document file:///tmp/loki-policy.json 2>/dev/null || echo "Policy '$POLICY_NAME' already exists in AWS."

# Cleanup
rm -f /tmp/loki-policy.json

echo "Done!"
