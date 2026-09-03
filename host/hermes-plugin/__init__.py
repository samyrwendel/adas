"""adas-hermes -- ADAS para o Hermes agent, mesma regra do Claude Code.

Dois mecanismos, cada um mapeado pra API de Hermes que resolve melhor o
mesmo problema que os 3 hooks do host/ (adas-activate.sh/adas-route.sh/
adas-subagent.sh) resolvem no Claude Code:

  * CONTEXTO: ``ctx.register_system_prompt_section(...)`` -- "bounded context
    que e CONGELADO em cada NOVO prompt de sessao" (doc do proprio Hermes).
    Isso cobre sozinho o que o Claude Code precisa de SessionStart pra
    resolver (reinjecao apos compactacao/resume) -- aqui o texto ja nasce
    dentro do prompt, nao precisa reinjetar depois. ``on_session_start``
    tambem e registrado, best-effort, caso a secao de prompt nao alcance
    sessao criada por um caminho que a pule (NAO PROVADO que seja
    necessario -- ver README).
  * SUBAGENT: ``subagent_start`` existe de verdade em Hermes (confirmado
    lendo plugins/observability/langfuse/__init__.py, que ja o registra) --
    ao contrario do que se poderia supor sem checar. Registrado aqui tambem,
    best-effort pelo mesmo motivo.
  * BLOQUEIO: ``pre_tool_call`` pode bloquear de verdade
    (``{"action": "block", "message": ...}``) -- mais forte que o Claude
    Code, que no ADAS de hoje so injeta contexto no PreToolUse e nunca
    recusa a ferramenta. Contrato e exemplo copiados do plugin de referencia
    real deste mesmo repo Hermes: plugins/security-guidance/__init__.py.

NENHUMA regra e reimplementada em Python: os tres pontos chamam os scripts
bash do host (adas-resolve.sh / adas-core.sh / adas-secret-guard.sh) via
subprocess -- a MESMA fonte que os hooks do Claude Code chamam.
"""

from __future__ import annotations

import os
import subprocess
from typing import Any, Optional


def _adas_home(configured: Optional[str] = None) -> Optional[str]:
    """Onde vivem os scripts do host/ -- NAO e a regra em si, e "onde acha o
    binario" (config, nao governanca). Env ADAS_HOME > config do plugin >
    ~/adas (default)."""
    for candidate in (os.environ.get("ADAS_HOME"), configured, os.path.expanduser("~/adas")):
        if candidate and os.path.isfile(os.path.join(candidate, "host", "adas-core.sh")):
            return candidate
    return None


def _run_host_script(adas_home: str, script: str, *args: str) -> str:
    try:
        out = subprocess.run(
            ["bash", os.path.join(adas_home, "host", script), *args],
            capture_output=True, text=True, timeout=2,
        )
        return (out.stdout or "").strip()
    except Exception:
        # fail-open: sem o host disponivel, ADAS fica inerte -- nunca quebra o turno.
        return ""


def _guess_cwd(session_info: Any) -> str:
    """session_info e um mapeamento read-only cujo schema exato nao esta
    documentado publicamente -- tenta as chaves mais prováveis, cai pro cwd
    do processo. NAO PROVADO qual chave (se alguma) o Hermes real usa; ver
    README, item nao verificado."""
    if isinstance(session_info, dict):
        for key in ("cwd", "workspace_dir", "working_dir", "project_dir", "workdir"):
            v = session_info.get(key)
            if isinstance(v, str) and v:
                return v
    return os.getcwd()


def _adas_core_for(session_info: Any = None) -> str:
    adas_home = _adas_home()
    if not adas_home:
        return ""
    cwd = _guess_cwd(session_info)
    repo = _run_host_script(adas_home, "adas-resolve.sh", cwd)
    if not repo:
        return ""
    return _run_host_script(adas_home, "adas-core.sh", repo)


def _on_session_start(**kwargs: Any) -> None:
    # Observation-only per VALID_HOOKS -- best-effort: so aqui pra provar,
    # via log, que a sessao passou por um repo governado. A injecao de
    # verdade e a register_system_prompt_section abaixo.
    pass


def _on_subagent_start(**kwargs: Any) -> None:
    pass


def _on_pre_tool_call(tool_name: str = "", args: Any = None, **_: Any) -> Optional[dict]:
    if tool_name not in ("exec", "bash", "shell", "run_command"):
        return None
    if not isinstance(args, dict):
        return None
    cmd = args.get("command") or args.get("cmd") or ""
    if not cmd:
        return None
    adas_home = _adas_home()
    if not adas_home:
        return None
    verdict = _run_host_script(adas_home, "adas-secret-guard.sh", cmd)
    if verdict.startswith("block:"):
        return {"action": "block", "message": verdict[len("block:"):]}
    return None


def register(ctx) -> None:
    ctx.register_system_prompt_section(
        "adas-core",
        content=_adas_core_for,
        position="after_memory",
    )
    ctx.register_hook("on_session_start", _on_session_start)
    ctx.register_hook("subagent_start", _on_subagent_start)
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
