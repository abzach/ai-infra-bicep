import argparse
import os
import sys
from typing import Dict

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from openai import AzureOpenAI


def load_settings() -> Dict[str, str]:
    """Load model connection settings from the .env file."""
    load_dotenv()

    endpoint = os.getenv('AZURE_OPENAI_ENDPOINT', '').strip()
    deployment = os.getenv('AZURE_OPENAI_DEPLOYMENT', '').strip()
    api_version = os.getenv('AZURE_OPENAI_API_VERSION', '2025-01-01-preview').strip()

    if not endpoint or not deployment:
        raise ValueError(
            'Missing configuration. Ensure AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT '
            'are set in .env (run the AI Chat shortcut to create it automatically on first launch).'
        )

    return {
        'endpoint': endpoint,
        'deployment': deployment,
        'api_version': api_version,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description='Run one prompt against the deployed Azure OpenAI model.')
    parser.add_argument('--prompt', default='Reply with OK only.', help='Prompt to send to the model.')
    args = parser.parse_args()

    try:
        settings = load_settings()
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(), 'https://cognitiveservices.azure.com/.default'
        )
        client = AzureOpenAI(
            azure_endpoint=settings['endpoint'],
            azure_ad_token_provider=token_provider,
            api_version=settings['api_version'],
        )

        response = client.chat.completions.create(
            model=settings['deployment'],
            messages=[
                {'role': 'system', 'content': 'You are a concise assistant.'},
                {'role': 'user', 'content': args.prompt},
            ],
            temperature=0,
            max_tokens=100,
        )

        answer = (response.choices[0].message.content or '').strip()
        if not answer:
            print('Test failed: empty model response.')
            return 1

        print('Test succeeded.')
        print(f'Model response: {answer}')
        return 0
    except Exception as ex:
        print(f'Test failed: {ex}')
        return 1


if __name__ == '__main__':
    sys.exit(main())
