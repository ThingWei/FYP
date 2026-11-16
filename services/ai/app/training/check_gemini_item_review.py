"""Read-only configuration/access diagnostic; never sends photos or prints credentials."""
import argparse
import json
from pathlib import Path

import httpx
from dotenv import load_dotenv

from app.services.gemini_item_review import MODEL, status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-access', action='store_true', help='Read model availability from Google; no image inference')
    args = parser.parse_args()
    load_dotenv(Path(__file__).resolve().parents[2] / '.env', override=False)
    info = status()
    info['access'] = 'not_checked'
    if args.check_access and info['configured']:
        import os
        try:
            response = httpx.get(f'https://generativelanguage.googleapis.com/v1beta/models/{MODEL}',
                                 headers={'x-goog-api-key': os.environ['GEMINI_API_KEY']},
                                 timeout=10, follow_redirects=False)
            info['access'] = 'available' if response.status_code == 200 and 'generateContent' in response.json().get('supportedGenerationMethods', []) else 'unavailable'
        except Exception:
            info['access'] = 'unavailable'
    info['freeTier'] = 'Verify the project tier and actual quota in Google AI Studio; this diagnostic cannot confirm billing status.'
    print(json.dumps(info))


if __name__ == '__main__':
    main()
