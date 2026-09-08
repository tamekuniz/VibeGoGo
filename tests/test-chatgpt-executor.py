import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / '.agents/skills/vibesdegogo/scripts/vdgg-exec-chatgpt.py'
spec = importlib.util.spec_from_file_location('executor', SCRIPT)
executor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(executor)
URL = 'https://chatgpt.com/c/fixture-123'


class ExecutorTests(unittest.TestCase):
    def test_rejects_wrong_identity_model_and_verdict(self):
        for answer, model, url in [
            ('REQUEST_ID: stale\nVERDICT: PASS\nreview', '6 Pro', URL),
            ('REQUEST_ID: id\nVERDICT: BLOCKED\nreview', '6 Pro', URL),
            ('REQUEST_ID: id\nVERDICT: PASS\nVERDICT: FAIL', '6 Pro', URL),
            ('REQUEST_ID: id\nVERDICT: PASS\nreview', '6 High', URL),
            ('REQUEST_ID: id\nVERDICT: PASS\nreview', '6 Pro', 'https://evil.example/c/id'),
        ]:
            with self.subTest(answer=answer, model=model, url=url), self.assertRaises(ValueError):
                executor.check_answer({'id': 'id'}, answer, model, url)

    def invoke(self, change=False, no_response=False, outside=False, formation=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / 'workspace'
            workspace.mkdir()
            source = (root if outside else workspace) / 'input.md'
            source.write_text('Review synthetic fixture')
            output = root / 'answer.md'
            env = dict(os.environ, VDGG_CHATGPT_WORKSPACE=str(workspace),
                       VDGG_CHATGPT_QUEUE=str(root / 'queue'), VDGG_CHATGPT_TIMEOUT='2',
                       VDGG_EXECUTOR_INPUT=str(source), VDGG_EXECUTOR_OUTPUT=str(output))
            command = [sys.executable, str(SCRIPT)]
            if formation:
                config = root / 'config'
                (config / 'formations').mkdir(parents=True)
                (config / 'executors').mkdir()
                (config / 'formations/probe.conf').write_text('4: chatgpt-web\n')
                (config / 'executors/chatgpt-web.conf').write_text(f'COMMAND={SCRIPT}\n')
                env.update(VDGG_CONFIG_DIR=str(config), VDGG_FORMATION='probe',
                           VDGG_CWD=str(workspace), VDGG_STATE_DIR=str(root / 'state'))
                command = ['bash', '-c',
                    'source "$1"; vdgg_formation_preflight probe; '
                    'vdgg_executor_run STEP_4_AI "$VDGG_EXECUTOR_INPUT" "$VDGG_EXECUTOR_OUTPUT"',
                    'formation-test', str(SCRIPT.with_name('vdgg-state.sh'))]
            proc = subprocess.Popen(command, env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                line = proc.stdout.readline()
                if outside:
                    self.assertNotEqual(proc.wait(timeout=5), 0)
                    self.assertFalse(output.exists())
                    return
                request_path = Path(json.loads(line)['request'])
                request = json.loads(request_path.read_text())
                answer = root / 'observed.md'
                answer.write_text(f'REQUEST_ID: {request["id"]}\nVERDICT: PASS\nReviewed the fixture; no blocking findings.\n')
                if change:
                    source.write_text('Changed after dispatch')
                if not no_response:
                    finished = subprocess.run([sys.executable, str(SCRIPT), 'complete',
                        '--request', str(request_path), '--answer', str(answer),
                        '--model', '6 Pro', '--chat-url', URL], capture_output=True)
                    self.assertEqual(finished.returncode, 1 if change else 0)
                    if not change:
                        duplicate = subprocess.run([sys.executable, str(SCRIPT), 'complete',
                            '--request', str(request_path), '--answer', str(answer),
                            '--model', '6 Pro', '--chat-url', URL], capture_output=True)
                        self.assertNotEqual(duplicate.returncode, 0)
                code = proc.wait(timeout=5)
                self.assertEqual(code, 1 if change or no_response else 0)
                if code:
                    self.assertFalse(output.exists())
                else:
                    self.assertEqual(output.read_text(), answer.read_text())
                self.assertEqual(json.loads(request_path.read_text())['status'], 'failed' if code else 'complete')
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
                proc.stdout.close()
                proc.stderr.close()

    def test_complete(self):
        self.invoke()

    def test_changed_input(self):
        self.invoke(change=True)

    def test_timeout_preserves_old_output_but_fails(self):
        self.invoke(no_response=True)

    def test_outside_workspace(self):
        self.invoke(outside=True)

    def test_current_formation_dispatch(self):
        self.invoke(formation=True)

    def test_current_formation_propagates_timeout(self):
        self.invoke(formation=True, no_response=True)


if __name__ == '__main__':
    unittest.main()
