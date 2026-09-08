#!/usr/bin/env python3
"""VDGG artifact executor serviced by the host agent's in-app browser.

No browser cookies, API keys, clipboard or browser automation here. The host
reads the request, uses codex-with-chatgpt, then supplies the observed answer.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temp.replace(path)


def check_answer(request, answer, model, url):
    if model != '6 Pro':
        raise ValueError('Expected visible Chat model 6 Pro')
    if not re.fullmatch(r'https://chatgpt\.com/(?:g/[^/]+/)?c/[a-zA-Z0-9-]+', url):
        raise ValueError('Expected actual ChatGPT conversation URL')
    if f'REQUEST_ID: {request["id"]}' not in answer.splitlines():
        raise ValueError('Answer request ID mismatch')
    verdicts = [line for line in answer.splitlines() if line.startswith('VERDICT:')]
    if verdicts != ['VERDICT: PASS']:
        raise ValueError('ChatGPT did not return exactly one PASS verdict')
    if len(answer.strip().splitlines()) < 3:
        raise ValueError('Answer must include substantive findings or a plan')


def complete(args):
    path = Path(args.request).resolve(strict=True)
    request = json.loads(path.read_text())
    if request['status'] != 'pending' or time.time() >= request['expires']:
        raise ValueError('Request is closed or expired')
    source = Path(request['input'])
    source.resolve(strict=True).relative_to(Path(request['workspace']))
    if digest(source) != request['sha256']:
        raise ValueError('Input changed since dispatch')
    answer = Path(args.answer).read_text()
    check_answer(request, answer, args.model, args.chat_url)
    response = dict(id=request['id'], sha256=request['sha256'],
                    workspace=request['workspace'], model=args.model,
                    chat_url=args.chat_url, answer=answer)
    destination = path.parent / 'response.json'
    if destination.exists():
        raise ValueError('Response already submitted')
    temporary = path.parent / (uuid.uuid4().hex + '.json')
    try:
        write_json(temporary, response)
        os.link(temporary, destination)  # Atomic publish; never replace a response.
    finally:
        temporary.unlink(missing_ok=True)


def run():
    workspace = Path(os.environ.get('VDGG_CHATGPT_WORKSPACE', os.getcwd())).resolve(strict=True)
    source = Path(os.environ['VDGG_EXECUTOR_INPUT']).resolve(strict=True)
    relative = source.relative_to(workspace)
    output = os.environ.get('VDGG_EXECUTOR_OUTPUT')
    if not output:
        raise ValueError('ChatGPT requires an output artifact; it never edits files')
    output = Path(output).absolute()
    if output.resolve() == source:
        raise ValueError('Output must not overwrite input')
    output_parent = output.parent.resolve(strict=True)
    if output.exists() or output.is_symlink():
        raise ValueError('Output already exists')
    timeout = int(os.environ.get('VDGG_CHATGPT_TIMEOUT', '1800'))
    if not 1 <= timeout <= 7200:
        raise ValueError('Timeout must be 1..7200 seconds')
    queue = Path(os.environ.get('VDGG_CHATGPT_QUEUE', str(Path.home() / '.local/state/vdgg/chatgpt')))
    queue.mkdir(parents=True, exist_ok=True, mode=0o700)
    job = queue / uuid.uuid4().hex
    job.mkdir(mode=0o700)
    request = dict(id=job.name, workspace=str(workspace), input=str(source),
                   relative_input=str(relative), sha256=digest(source),
                   step=os.environ.get('VDGG_EXECUTOR_STEP', ''), model='6 Pro',
                   output=str(output), status='pending', expires=time.time() + timeout)
    write_json(job / 'request.json', request)
    print(json.dumps({'service': 'codex-with-chatgpt', 'request': str(job / 'request.json'),
                      'instruction': 'Host: verify doctor/workspace/6 Pro, ask ChatGPT to read the input through MCP, then complete with the observed answer.'}), flush=True)
    try:
        while time.time() < request['expires']:
            response_path = job / 'response.json'
            if response_path.exists():
                response = json.loads(response_path.read_text())
                for key in ('id', 'workspace', 'sha256'):
                    if response.get(key) != request[key]:
                        raise ValueError(f'Response {key} mismatch')
                if source.resolve(strict=True) != source or digest(source) != request['sha256']:
                    raise ValueError('Input changed while awaiting ChatGPT')
                check_answer(request, response['answer'], response['model'], response['chat_url'])
                # Never consume an old output when this request fails.
                if output.parent.resolve(strict=True) != output_parent:
                    raise ValueError('Output parent changed')
                with output.open('x') as stream:
                    stream.write(response['answer'])
                request['status'] = 'complete'
                return
            time.sleep(0.2)
        raise TimeoutError('ChatGPT response timed out; no automatic model fallback')
    finally:
        if request['status'] == 'pending':
            request['status'] = 'failed'
        write_json(job / 'request.json', request)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command')
    finish = commands.add_parser('complete')
    for name in ('request', 'answer', 'model', 'chat-url'):
        finish.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        complete(args) if args.command == 'complete' else run()
    except (OSError, ValueError, KeyError, TimeoutError) as error:
        print(f'vdgg-chatgpt: BLOCKED: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
