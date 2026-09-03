"""Prova por efeito, sem um Hermes real rodando: este mock implementa só
``register_hook``/``register_system_prompt_section`` (a superfície de ``ctx``
documentada em hermes_cli/plugins.py, lida via SSH read-only em clawdgo) e
captura os callables reais que ``register()`` registrou -- dali em diante é
código de PRODUÇÃO sendo exercitado, não um dublê da lógica.

Os scripts do host/ NÃO são mockados -- rodam de verdade via subprocess
contra um fixture de repo/ADAS.md em tmpdir, igual em produção.

Uso: cd host/hermes-plugin && python3 -m pytest test_adas_hermes.py -v
"""
from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
import __init__ as adas_hermes  # noqa: E402


class _FakeCtx:
    def __init__(self):
        self.hooks: dict[str, list] = {}
        self.prompt_sections: dict[str, object] = {}

    def register_hook(self, hook_name, callback):
        self.hooks.setdefault(hook_name, []).append(callback)

    def register_system_prompt_section(self, id, content, *, position="after_memory", max_chars=None):
        self.prompt_sections[id] = content


def _build_fixture():
    base = tempfile.mkdtemp(prefix="adas-hermes-test-")
    adas_home = os.path.join(base, "adas")
    host_dir = os.path.join(adas_home, "host")
    os.makedirs(host_dir, exist_ok=True)
    repo = os.path.join(base, "repo")
    os.makedirs(repo, exist_ok=True)
    with open(os.path.join(repo, "ADAS.md"), "w") as f:
        f.write("# Repo teste\n<!-- adas-core-start -->\nNUCLEO-DE-TESTE-HERMES\n<!-- adas-core-end -->\n")
    with open(os.path.join(base, "repos.conf"), "w") as f:
        f.write(repo + "\n")
    real_host = os.path.join(os.path.dirname(__file__), "..")
    for fname in ("adas-lib.sh", "adas-resolve.sh", "adas-core.sh", "adas-secret-guard.sh"):
        src = os.path.join(real_host, fname)
        dst = os.path.join(host_dir, fname)
        shutil.copyfile(src, dst)
        os.chmod(dst, os.stat(dst).st_mode | stat.S_IEXEC)
    os.environ["ADAS_REPOS_CONF"] = os.path.join(base, "repos.conf")
    return adas_home, repo


def setup_module(module):
    module.ADAS_HOME, module.REPO = _build_fixture()
    os.environ["ADAS_HOME"] = module.ADAS_HOME


def test_register_installs_hooks_and_prompt_section():
    ctx = _FakeCtx()
    adas_hermes.register(ctx)
    assert "adas-core" in ctx.prompt_sections
    assert "on_session_start" in ctx.hooks
    assert "subagent_start" in ctx.hooks
    assert "pre_tool_call" in ctx.hooks


def test_prompt_section_injects_core_from_governed_repo():
    ctx = _FakeCtx()
    adas_hermes.register(ctx)
    content_fn = ctx.prompt_sections["adas-core"]
    result = content_fn({"cwd": REPO})
    assert "NUCLEO-DE-TESTE-HERMES" in result


def test_prompt_section_silent_outside_governed_repo():
    ctx = _FakeCtx()
    adas_hermes.register(ctx)
    content_fn = ctx.prompt_sections["adas-core"]
    result = content_fn({"cwd": "/tmp/nao-e-governado-xyz"})
    assert result == ""


def test_pre_tool_call_blocks_env_read():
    ctx = _FakeCtx()
    adas_hermes.register(ctx)
    handler = ctx.hooks["pre_tool_call"][0]
    result = handler(tool_name="exec", args={"command": "cat .env"})
    assert result is not None
    assert result["action"] == "block"
    assert "seguranca-acesso" in result["message"]


def test_pre_tool_call_allows_safe_command():
    ctx = _FakeCtx()
    adas_hermes.register(ctx)
    handler = ctx.hooks["pre_tool_call"][0]
    result = handler(tool_name="exec", args={"command": "ls -la"})
    assert result is None


def test_pre_tool_call_ignores_non_shell_tools():
    ctx = _FakeCtx()
    adas_hermes.register(ctx)
    handler = ctx.hooks["pre_tool_call"][0]
    result = handler(tool_name="web_search", args={"query": "cat .env"})
    assert result is None


def teardown_module(module):
    os.environ.pop("ADAS_HOME", None)
    os.environ.pop("ADAS_REPOS_CONF", None)
