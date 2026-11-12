"""Redator mínimo do ADAS: usado pelo juiz quando ADAS_REDATOR não está configurado (task 20261112-012, N5).

Apaga os formatos INEQUÍVOCOS de credencial, mais o valor das variáveis de ambiente com nome de segredo.
A instância que tem cofre aponta ADAS_REDATOR para o redator dela, que também apaga o valor do cofre.
Mesma interface: carregar_segredos() → [valores]; redigir(texto, segredos) → (texto, motivos).
Os padrões são os do redator da frota Axon, onde o falso positivo de cada um já foi medido.
"""
import os
import re

MARCA = "«redigido»"
_NOME_SEGREDO = re.compile(r"(KEY|TOKEN|SECRET|PASSW|PASSWORD|CREDENTIAL)S?$", re.I)

PADROES = [
    # lookbehind: o "sk-" de "ta|sk-018.md" não é chave; chave de verdade tem dígito
    ("chave OpenAI/Anthropic", re.compile(r"(?<![A-Za-z0-9_])sk-(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{16,}")),
    ("token GitHub", re.compile(r"\b(?:ghp_[A-Za-z0-9]{36}|gh[osu]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,})")),
    ("chave Google", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("chave AWS", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("token Slack", re.compile(r"\bxox[baprs]-[0-9A-Za-z-]{10,}")),
    ("token de bot do Telegram", re.compile(r"\b[0-9]{8,10}:AA[A-Za-z0-9_-]{33}\b")),
    ("Read-Only Token da Lighter", re.compile(r"\bro:\d+:[a-z]+:\d+:[0-9a-fA-F]{32,}")),
    ("Bearer literal", re.compile(r"(?i)(bearer\s+)([A-Za-z0-9._~+/-]{16,}=*)")),
    ("bloco PEM de chave privada",
     re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S)),
    ("campo de segredo com valor",
     re.compile(r"""(?ix)
        (["']?\b(?:private[_-]?key|secret[_-]?key|client[_-]?secret|api[_-]?key|
                  access[_-]?token|refresh[_-]?token|auth[_-]?token|bot[_-]?token|
                  password|passwd|secret|seed[_-]?phrase|mnemonic)\b["']?
         \s*[:=]\s*["']?)
        ([A-Za-z0-9._~+/=-]{16,})
     """)),
]
_COM_ROTULO = {"Bearer literal", "campo de segredo com valor"}  # 2 grupos: preserva o rótulo, apaga o valor


def _credencial(v):
    """Depois de rótulo, só condena valor que mistura letra e dígito (`client_secret: cfg.client_secret` é código)."""
    return len(v) >= 16 and any(c.isdigit() for c in v) and any(c.isalpha() for c in v)


def carregar_segredos():
    """Valores das variáveis de ambiente com nome de segredo (≥12 caracteres), maiores primeiro."""
    vals = {v for k, v in os.environ.items() if _NOME_SEGREDO.search(k) and len(v) >= 12}
    return sorted(vals, key=len, reverse=True)


def redigir(texto, segredos=None):
    """→ (texto_limpo, motivos). Os motivos nomeiam o que casou, nunca o valor."""
    motivos = []
    for s in carregar_segredos() if segredos is None else segredos:
        if s and s in texto:
            texto = texto.replace(s, MARCA)
            motivos.append("valor de variável de segredo")
    for nome, rx in PADROES:
        n = 0

        def troca(m, nome=nome):
            nonlocal n
            if nome in _COM_ROTULO:
                if not _credencial(m.group(2)):
                    return m.group(0)
                n += 1
                return m.group(1) + MARCA
            n += 1
            return MARCA

        texto = rx.sub(troca, texto)
        motivos += [nome] * n
    return texto, motivos


if __name__ == "__main__":  # self-check: cada formato cai, código com rótulo fica
    a = "abcdefghij0123456789ABCDEFGHIJ0123456789"
    falsas = ["sk-" + "proj" + a[:30], "gh" + "p_" + a[:36], "AI" + "za" + a[:35], "AK" + "IA" + "ABCDEFGHIJ012345",
              "xox" + "b-" + a[:20], "1234567890:" + "AA" + a[:33], "ro:" + "1:abc:2:" + "ab12" * 8,
              "-----BEGIN " + "PRIVATE KEY-----\n" + a + "\n-----END " + "PRIVATE KEY-----", "Bearer " + a, "api_key=" + a]
    for f in falsas:
        t, m = redigir("x " + f + " y", [])
        assert a[:16] not in t and "ABCDEFGHIJ012345" not in t and m, (f[:12], t)
    assert redigir("client_secret: cfg.client_secret", [])[0] == "client_secret: cfg.client_secret"
    assert redigir("ta|sk-018.md", [])[0] == "ta|sk-018.md"
    os.environ["X_API_KEY"] = "valor-qualquer-123"
    assert redigir("tem valor-qualquer-123 aqui")[0] == "tem «redigido» aqui"
    print("redator_min: ok")
